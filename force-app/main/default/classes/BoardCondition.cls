/**
 * The condition model: one structured condition tree (filter id, path, operator, values, AND/OR nodes) that Filter
 * bindings (after resolution) and Base filters build. A tree compiles to a bind-safe `SOQL` `WHERE` clause and also
 * evaluates in memory against a row (a map of path to value) with `SOQL` semantics: case-insensitive text, `NULL`s
 * only match `= null` / `!= value` / `NOT IN` / `EXCLUDES`, relative date literals in the user's time zone.
 *
 * Predicate operators and their `values`:
 * - `EQ`, `NEQ`, `GT`, `GTE`, `LT`, `LTE`: one typed value (`EQ` / `NEQ` accept null).
 * - `IN`, `NOT_IN`: a typed list, bound as one list (its runtime element type must match the field).
 * - `INCLUDES`, `EXCLUDES`: multi-select picklist tokens, each `a;b` meaning both values.
 * - `LIKE`: one `SOQL LIKE` pattern (`%`, `_`, `\` escapes).
 * - `RELATIVE_DATE`: one relative date literal (e.g. `LAST_N_DAYS:30`, `THIS_FISCAL_QUARTER`).
 */
public inherited sharing class BoardCondition {
    private static final Set<String> COMPARISONS = new Set<String>{ 'EQ', 'NEQ', 'GT', 'GTE', 'LT', 'LTE' };
    private static final Set<String> OPERATORS = new Set<String>{
        'EQ',
        'NEQ',
        'GT',
        'GTE',
        'LT',
        'LTE',
        'IN',
        'NOT_IN',
        'INCLUDES',
        'EXCLUDES',
        'LIKE',
        'RELATIVE_DATE'
    };
    private static final Map<String, String> SYMBOLS = new Map<String, String>{
        'EQ' => '=',
        'NEQ' => '!=',
        'GT' => '>',
        'GTE' => '>=',
        'LT' => '<',
        'LTE' => '<='
    };
    private static final Pattern RELATIVE_DATE_PATTERN = Pattern.compile(
        '^(YESTERDAY|TODAY|TOMORROW|(LAST|THIS|NEXT)_(WEEK|MONTH|QUARTER|YEAR|FISCAL_QUARTER|FISCAL_YEAR)' +
            '|(LAST|NEXT)_90_DAYS|(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|QUARTERS|YEARS|FISCAL_QUARTERS|FISCAL_YEARS):\\d{1,4}' +
            '|N_(DAYS|WEEKS|MONTHS|QUARTERS|YEARS|FISCAL_QUARTERS|FISCAL_YEARS)_AGO:\\d{1,4})$'
    );
    private static Integer fiscalYearStartMonth;

    /** Turns a typed value into a `SOQL` bind reference (`:name`); `isLikePattern` marks escaped `LIKE` patterns. */
    public interface Binder {
        String bind(Object value, Boolean isLikePattern);
    }

    /**
     * A condition value whose `SOQL` form is not what an in-memory row holds (a currency ISO literal): in memory the
     * row is compared with `inMemoryValue()` instead (a currency amount: in the corporate currency, like the row).
     */
    public interface InMemoryOperand {
        Object inMemoryValue();
    }

    /** A node of the condition tree. */
    public abstract class Node {
        /** The `SOQL` `WHERE` expression of this node; values go through `binder`, never inline. */
        public abstract String toSoql(Binder binder);
        /** Whether `row` (path to value) satisfies this node with `SOQL` semantics. */
        public abstract Boolean evaluate(Map<String, Object> row);
    }

    /** An AND / OR node over child nodes (an empty AND is true, an empty OR is false). */
    public class Junction extends Node {
        public String logic;
        public List<Node> children;

        public Junction(String logic, List<Node> children) {
            this.logic = logic;
            this.children = children == null ? new List<Node>() : children;
        }

        public override String toSoql(Binder binder) {
            List<String> clauses = new List<String>();
            for (Node child : children) {
                clauses.add(child.toSoql(binder));
            }
            return clauses.size() == 1 ? clauses[0] : '(' + String.join(clauses, ') ' + logic + ' (') + ')';
        }

        public override Boolean evaluate(Map<String, Object> row) {
            Boolean isAnd = logic == 'AND';
            for (Node child : children) {
                if (child.evaluate(row) != isAnd) {
                    return !isAnd;
                }
            }
            return isAnd;
        }
    }

    /** One condition on one field path. */
    public class Predicate extends Node {
        /** The Filter id or Base filter id this condition came from. */
        public String filterId;
        public String path;
        public String operator;
        public List<Object> values;
        /** True when a `LIKE` pattern's user text is already escaped (its `\` sequences must survive inlining). */
        public Boolean escapedPattern = false;

        public Predicate(String filterId, String path, String operator, List<Object> values) {
            if (!OPERATORS.contains(operator)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unsupported condition operator: ' + operator,
                    filterId,
                    path
                );
            }
            this.filterId = filterId;
            this.path = path;
            this.operator = operator;
            this.values = values == null ? new List<Object>() : values;
        }

        Object operand() {
            return values.isEmpty() ? null : values[0];
        }

        /** `value` as an in-memory row value compares with it. */
        Object inMemory(Object value) {
            return value instanceof InMemoryOperand ? ((InMemoryOperand) value).inMemoryValue() : value;
        }

        public override String toSoql(Binder binder) {
            if (COMPARISONS.contains(operator)) {
                Object first = operand();
                return path + ' ' + SYMBOLS.get(operator) + ' ' + (first == null ? 'null' : binder.bind(first, false));
            }
            switch on operator {
                when 'IN', 'NOT_IN' {
                    return path + (operator == 'IN' ? ' IN ' : ' NOT IN ') + binder.bind(values, false);
                }
                when 'INCLUDES', 'EXCLUDES' {
                    List<String> tokens = new List<String>();
                    for (Object value : values) {
                        Object token = value;
                        if (token == null) {
                            token = '';
                        }
                        tokens.add(binder.bind(token, false));
                    }
                    return path + ' ' + operator + ' (' + String.join(tokens, ', ') + ')';
                }
                when 'LIKE' {
                    return path + ' LIKE ' + binder.bind(operand(), escapedPattern);
                }
                when else {
                    return path + ' = ' + requireRelativeDate(operand());
                }
            }
        }

        public override Boolean evaluate(Map<String, Object> row) {
            Object actual = row.get(path);
            if (COMPARISONS.contains(operator)) {
                return compareMatches(actual, inMemory(operand()));
            }
            switch on operator {
                when 'IN' {
                    return inList(actual);
                }
                when 'NOT_IN' {
                    return !inList(actual);
                }
                when 'INCLUDES' {
                    return includesAny(actual);
                }
                when 'EXCLUDES' {
                    return !includesAny(actual);
                }
                when 'LIKE' {
                    return actual != null && likeMatches(String.valueOf(actual), String.valueOf(operand()));
                }
                when else {
                    if (actual == null) {
                        return false;
                    }
                    Date day = actual instanceof Datetime ? ((Datetime) actual).date() : (Date) actual;
                    List<Date> range = relativeRange(requireRelativeDate(operand()), Date.today());
                    return day >= range[0] && day <= range[1];
                }
            }
        }

        Boolean compareMatches(Object actual, Object expected) {
            if (expected == null) {
                // `= null` / `!= null`; ordering against null never matches.
                return operator == 'EQ' ? actual == null : operator == 'NEQ' && actual != null;
            }
            if (actual == null) {
                // `SOQL` `!= value` keeps rows whose field is empty.
                return operator == 'NEQ';
            }
            Integer order = compareValues(actual, expected);
            switch on operator {
                when 'EQ' {
                    return order == 0;
                }
                when 'NEQ' {
                    return order != 0;
                }
                when 'GT' {
                    return order > 0;
                }
                when 'GTE' {
                    return order >= 0;
                }
                when 'LT' {
                    return order < 0;
                }
                when else {
                    return order <= 0;
                }
            }
        }

        Boolean inList(Object actual) {
            for (Object listed : values) {
                Object value = inMemory(listed);
                if (actual == null ? value == null : value != null && compareValues(actual, value) == 0) {
                    return true;
                }
            }
            return false;
        }

        /** Multi-select `INCLUDES`: some token's `;`-separated values are all selected (case-insensitive). */
        Boolean includesAny(Object actual) {
            if (actual == null) {
                return false;
            }
            Set<String> selected = splitTokens(String.valueOf(actual));
            for (Object value : values) {
                Set<String> required = splitTokens(value == null ? '' : String.valueOf(value));
                if (!required.isEmpty() && selected.containsAll(required)) {
                    return true;
                }
            }
            return false;
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Builders
    // ---------------------------------------------------------------------------------------------------------

    public static Predicate field(String filterId, String path, String operator, List<Object> values) {
        return new Predicate(filterId, path, operator, values);
    }

    /**
     * A condition on an Integer or Long field (`isLong`): SOQL rejects a Decimal bind on such a column, so values bind
     * as whole numbers. A non-whole comparison value becomes the equivalent whole-number comparison (`>= 11.5` →
     * `>= 12`, `> 11.5` → `>= 12`, `<= 11.5` → `<= 11`, `< 11.5` → `<= 11`); `= 11.5` matches nothing and `!= 11.5`
     * everything. IN / NOT IN drop non-whole values (none left: IN matches nothing, NOT IN everything). Other
     * operators are unchanged. `SOQL` and in-memory evaluation agree.
     */
    public static Node wholeNumberField(
        String filterId,
        String path,
        String operator,
        List<Object> values,
        Boolean isLong
    ) {
        List<Object> given = values == null ? new List<Object>() : values;
        if (operator == 'IN' || operator == 'NOT_IN') {
            List<Object> kept = isLong ? (List<Object>) new List<Long>() : (List<Object>) new List<Integer>();
            for (Object value : given) {
                Decimal amount = value == null ? null : BoardQueryService.toDecimal(value);
                if (amount != null && isWhole(amount)) {
                    kept.add(asWhole(amount, isLong));
                }
            }
            if (kept.isEmpty()) {
                return operator == 'IN' ? matchesNothing(filterId, path) : matchesEverything(filterId, path);
            }
            return field(filterId, path, operator, kept);
        }
        if (!COMPARISONS.contains(operator) || given.isEmpty() || given[0] == null) {
            return field(filterId, path, operator, given);
        }
        Decimal amount = BoardQueryService.toDecimal(given[0]);
        if (isWhole(amount)) {
            return field(filterId, path, operator, new List<Object>{ asWhole(amount, isLong) });
        }
        switch on operator {
            when 'GT', 'GTE' {
                Decimal bound = amount.round(System.RoundingMode.CEILING);
                return field(filterId, path, 'GTE', new List<Object>{ asWhole(bound, isLong) });
            }
            when 'LT', 'LTE' {
                Decimal bound = amount.round(System.RoundingMode.FLOOR);
                return field(filterId, path, 'LTE', new List<Object>{ asWhole(bound, isLong) });
            }
            when 'EQ' {
                return matchesNothing(filterId, path);
            }
            when else {
                return matchesEverything(filterId, path);
            }
        }
    }

    private static Boolean isWhole(Decimal amount) {
        return amount == amount.round(System.RoundingMode.DOWN);
    }

    private static Object asWhole(Decimal amount, Boolean isLong) {
        return isLong ? (Object) amount.longValue() : (Object) amount.intValue();
    }

    /** `path = null AND path != null`: no row. */
    private static Node matchesNothing(String filterId, String path) {
        return allOf(
            new List<Node>{
                field(filterId, path, 'EQ', new List<Object>{ null }),
                field(filterId, path, 'NEQ', new List<Object>{ null })
            }
        );
    }

    /** `path = null OR path != null`: every row. */
    private static Node matchesEverything(String filterId, String path) {
        return anyOf(
            new List<Node>{
                field(filterId, path, 'EQ', new List<Object>{ null }),
                field(filterId, path, 'NEQ', new List<Object>{ null })
            }
        );
    }

    public static Junction allOf(List<Node> children) {
        return new Junction('AND', children);
    }

    public static Junction anyOf(List<Node> children) {
        return new Junction('OR', children);
    }

    /** Whether `literal` is a supported relative date literal (already trimmed and upper-cased). */
    public static Boolean isRelativeDate(String literal) {
        return literal != null && RELATIVE_DATE_PATTERN.matcher(literal).matches();
    }

    // ---------------------------------------------------------------------------------------------------------
    // SOQL semantics
    // ---------------------------------------------------------------------------------------------------------

    private static String requireRelativeDate(Object value) {
        String literal = value == null ? null : String.valueOf(value).trim().toUpperCase();
        if (!isRelativeDate(literal)) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Invalid relative date literal: ' + value, null, null);
        }
        return literal;
    }

    /** `SOQL` ordering of two non-null values: numbers, dates, datetimes, Ids, booleans, case-insensitive text. */
    private static Integer compareValues(Object left, Object right) {
        if (isNumber(left) && isNumber(right)) {
            Decimal a = BoardQueryService.toDecimal(left);
            Decimal b = BoardQueryService.toDecimal(right);
            return a == b ? 0 : (a < b ? -1 : 1);
        }
        if (left instanceof Datetime && right instanceof Datetime) {
            Long a = ((Datetime) left).getTime();
            Long b = ((Datetime) right).getTime();
            return a == b ? 0 : (a < b ? -1 : 1);
        }
        if (left instanceof Date && right instanceof Date) {
            Date a = (Date) left;
            Date b = (Date) right;
            return a == b ? 0 : (a < b ? -1 : 1);
        }
        if (left instanceof Boolean || right instanceof Boolean) {
            return String.valueOf(left).equalsIgnoreCase(String.valueOf(right)) ? 0 : 1;
        }
        String a = String.valueOf(left);
        String b = String.valueOf(right);
        if (left instanceof Id || right instanceof Id) {
            a = normalizeId(a);
            b = normalizeId(b);
        }
        return a.toLowerCase().compareTo(b.toLowerCase());
    }

    private static Boolean isNumber(Object value) {
        return value instanceof Integer || value instanceof Long || value instanceof Double || value instanceof Decimal;
    }

    /** 18-character form of a 15- or 18-character Id, so both forms compare equal. */
    private static String normalizeId(String value) {
        try {
            return String.valueOf(Id.valueOf(value));
        } catch (Exception notAnId) {
            return value;
        }
    }

    private static Set<String> splitTokens(String value) {
        Set<String> tokens = new Set<String>();
        for (String token : value.split(';')) {
            if (String.isNotBlank(token)) {
                tokens.add(token.trim().toLowerCase());
            }
        }
        return tokens;
    }

    /** Whole-value, case-insensitive `SOQL LIKE` match (`%` any run, `_` one character, `\` escapes the next). */
    private static Boolean likeMatches(String actual, String likePattern) {
        if (likePattern == null) {
            return false;
        }
        String regex = '';
        String literal = '';
        Integer i = 0;
        while (i < likePattern.length()) {
            String ch = likePattern.substring(i, i + 1);
            if (ch == '\\' && i + 1 < likePattern.length()) {
                literal += likePattern.substring(i + 1, i + 2);
                i += 2;
                continue;
            }
            if (ch == '%' || ch == '_') {
                regex += (literal == '' ? '' : Pattern.quote(literal)) + (ch == '%' ? '.*' : '.');
                literal = '';
            } else {
                literal += ch;
            }
            i++;
        }
        regex += literal == '' ? '' : Pattern.quote(literal);
        return Pattern.compile('(?is)' + regex).matcher(actual).matches();
    }

    // ---------------------------------------------------------------------------------------------------------
    // Relative date literals
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Inclusive `[start, end]` days a relative date literal covers on `today`. `LAST_N_DAYS:n` runs from `n` days
     * ago through today; `NEXT_N_DAYS:n` from tomorrow for `n` days; `LAST_N_<period>S:n` / `NEXT_N_<period>S:n`
     * cover whole periods before / after the current one; `N_<period>S_AGO:n` is the one period `n` periods back.
     * Weeks start on the user locale's first day; fiscal periods follow the org's fiscal year start month.
     */
    @TestVisible
    private static List<Date> relativeRange(String literal, Date today) {
        switch on literal {
            when 'TODAY' {
                return new List<Date>{ today, today };
            }
            when 'YESTERDAY' {
                return new List<Date>{ today.addDays(-1), today.addDays(-1) };
            }
            when 'TOMORROW' {
                return new List<Date>{ today.addDays(1), today.addDays(1) };
            }
            when 'LAST_90_DAYS' {
                literal = 'LAST_N_DAYS:90';
            }
            when 'NEXT_90_DAYS' {
                literal = 'NEXT_N_DAYS:90';
            }
        }
        List<String> parts = literal.split(':');
        String head = parts[0];
        Integer n = parts.size() > 1 ? Integer.valueOf(parts[1]) : 1;
        if (head.startsWith('N_') && head.endsWith('_AGO')) {
            String unit = singular(head.substring(2, head.length() - 4));
            return periodRange(unit, today, -n, -n + 1);
        }
        if (head.startsWith('LAST_N_') || head.startsWith('NEXT_N_')) {
            String unit = singular(head.substring(7));
            Boolean isLast = head.startsWith('LAST_');
            if (unit == 'DAY') {
                return isLast
                    ? new List<Date>{ today.addDays(-n), today }
                    : new List<Date>{ today.addDays(1), today.addDays(n) };
            }
            return isLast ? periodRange(unit, today, -n, 0) : periodRange(unit, today, 1, n + 1);
        }
        Integer offset = head.startsWith('LAST_') ? -1 : (head.startsWith('NEXT_') ? 1 : 0);
        return periodRange(head.substring(5), today, offset, offset + 1);
    }

    /** `[start of period fromOffset, day before start of period toOffset]` relative to the period holding `today`. */
    private static List<Date> periodRange(String unit, Date today, Integer fromOffset, Integer toOffset) {
        return new List<Date>{ periodStart(unit, today, fromOffset), periodStart(unit, today, toOffset).addDays(-1) };
    }

    private static Date periodStart(String unit, Date today, Integer offset) {
        switch on unit {
            when 'DAY' {
                return today.addDays(offset);
            }
            when 'WEEK' {
                return today.toStartOfWeek().addDays(7 * offset);
            }
            when 'MONTH' {
                return monthPeriodStart(today, 1, 1, offset);
            }
            when 'QUARTER' {
                return monthPeriodStart(today, 3, 1, offset);
            }
            when 'YEAR' {
                return monthPeriodStart(today, 12, 1, offset);
            }
            when 'FISCAL_QUARTER' {
                return monthPeriodStart(today, 3, getFiscalYearStartMonth(), offset);
            }
            when else {
                // FISCAL_YEAR
                return monthPeriodStart(today, 12, getFiscalYearStartMonth(), offset);
            }
        }
    }

    /** First day of the `months`-long period (aligned to `anchorMonth`) `offset` periods from the one holding `day`. */
    private static Date monthPeriodStart(Date day, Integer months, Integer anchorMonth, Integer offset) {
        Integer anchor = anchorMonth - 1;
        Integer monthIndex = day.year() * 12 + day.month() - 1;
        Integer startIndex = ((monthIndex - anchor) / months + offset) * months + anchor;
        return Date.newInstance(startIndex / 12, Math.mod(startIndex, 12) + 1, 1);
    }

    private static String singular(String unit) {
        return unit.endsWith('S') ? unit.substring(0, unit.length() - 1) : unit;
    }

    /** The org's standard fiscal year start month (1 = January). */
    private static Integer getFiscalYearStartMonth() {
        if (fiscalYearStartMonth == null) {
            Organization settings = [SELECT FiscalYearStartMonth FROM Organization WITH USER_MODE LIMIT 1];
            fiscalYearStartMonth = settings.FiscalYearStartMonth == null ? 1 : settings.FiscalYearStartMonth;
        }
        return fiscalYearStartMonth;
    }
}