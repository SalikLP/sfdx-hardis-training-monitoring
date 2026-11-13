/**
 * A Bucket field: an ordered list of rules (a condition tree plus a label) that labels each row with the first rule it
 * matches, else with the fallback bucket (default "Other"), or leaves the row out when the fallback excludes.
 *
 * Config shape: `{ id, label, rules: [{ label, condition, colour }], fallback: { label, exclude } }`, 1 to 25 rules. A
 * rule `condition` uses the Base filter condition shape (one condition, or `{ logic, conditions[] }` with AND / OR
 * groups); Widgets reference a Bucket field as `bucket:<id>` wherever they take a group or series field.
 *
 * Rules arrive as raw config (`fromConfig`); a query scope compiles each rule's `condition` node and `soql`. Then a row
 * gets its bucket in memory (`labelOf`), or each bucket becomes one `SOQL` predicate (`predicates`): bucket `i` is
 * `rule_i AND NOT(rule_1..i-1)`, OR'd across rules sharing a label; the fallback is `NOT(every rule)`.
 */
public inherited sharing class BoardBucketField {
    public static final Integer MAX_RULES = 25;
    public static final String DEFAULT_FALLBACK_LABEL = 'Other';
    /** Prefix of a Bucket field reference in a group or series field (`bucket:<id>`). */
    public static final String REFERENCE_PREFIX = 'bucket:';
    /** The operator matching exactly the rows (empty fields aside) a predicate operator doesn't. */
    private static final Map<String, String> FLIPPED_OPERATORS = new Map<String, String>{
        'EQ' => 'NEQ',
        'NEQ' => 'EQ',
        'GT' => 'LTE',
        'GTE' => 'LT',
        'LT' => 'GTE',
        'LTE' => 'GT',
        'IN' => 'NOT_IN',
        'NOT_IN' => 'IN',
        'INCLUDES' => 'EXCLUDES',
        'EXCLUDES' => 'INCLUDES'
    };

    public String id;
    public String label;
    public List<Rule> rules;
    public String fallbackLabel;
    public Boolean excludeFallback;

    /** One rule: rows matching `condition` (and no earlier rule) get `label`. */
    public class Rule {
        public String label;
        /** Colour of the rule's bucket in charts (optional). */
        public String colour;
        /** The rule's condition as configured (compiled by a query scope into `condition` and `soql`). */
        public Object rawCondition;
        public BoardCondition.Node condition;
        /** The compiled `SOQL` of `condition`; when null, `predicates` compiles `condition` itself. */
        public String soql;

        public Rule(String label, BoardCondition.Node condition) {
            this.label = label;
            this.condition = condition;
        }
    }

    public BoardBucketField(String id, String label, List<Rule> rules, String fallbackLabel, Boolean excludeFallback) {
        this.id = id;
        this.label = label;
        this.rules = rules == null ? new List<Rule>() : rules;
        this.fallbackLabel = String.isBlank(fallbackLabel) ? DEFAULT_FALLBACK_LABEL : fallbackLabel.trim();
        this.excludeFallback = excludeFallback == true;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Evaluation
    // ---------------------------------------------------------------------------------------------------------

    /** The bucket of `row` (path to value): the first matching rule's label, the fallback label, or null (excluded). */
    public String labelOf(Map<String, Object> row) {
        for (Rule rule : rules) {
            if (rule.condition.evaluate(row)) {
                return rule.label;
            }
        }
        return excludeFallback ? null : fallbackLabel;
    }

    /** Every field path the compiled rule conditions read, once each in rule order (the row keys `labelOf` needs). */
    public List<String> paths() {
        List<String> ordered = new List<String>();
        for (Rule rule : rules) {
            collectPaths(rule.condition, ordered);
        }
        return ordered;
    }

    private static void collectPaths(BoardCondition.Node node, List<String> ordered) {
        if (node instanceof BoardCondition.Junction) {
            for (BoardCondition.Node child : ((BoardCondition.Junction) node).children) {
                collectPaths(child, ordered);
            }
            return;
        }
        String path = ((BoardCondition.Predicate) node).path;
        if (!ordered.contains(path)) {
            ordered.add(path);
        }
    }

    /** Every bucket label once, in rule order, then the fallback label unless excluded. */
    public List<String> labels() {
        List<String> ordered = new List<String>();
        Set<String> seen = new Set<String>();
        for (Rule rule : rules) {
            if (seen.add(rule.label)) {
                ordered.add(rule.label);
            }
        }
        if (!excludeFallback && seen.add(fallbackLabel)) {
            ordered.add(fallbackLabel);
        }
        return ordered;
    }

    /** One `SOQL` predicate per bucket label (see the class comment); values bind through `binder`. */
    public Map<String, String> predicates(BoardCondition.Binder binder) {
        List<String> ruleSoql = new List<String>();
        for (Rule rule : rules) {
            ruleSoql.add(rule.soql != null ? rule.soql : rule.condition.toSoql(binder));
        }
        List<String> negatedSoql = new List<String>();
        for (Rule rule : rules) {
            negatedSoql.add(negate(rule.condition, binder));
        }
        Map<String, List<String>> alternatives = new Map<String, List<String>>();
        for (Integer i = 0; i < rules.size(); i++) {
            List<String> parts = new List<String>{ ruleSoql[i] };
            for (Integer j = 0; j < i; j++) {
                parts.add(negatedSoql[j]);
            }
            addAlternative(alternatives, rules[i].label, parts);
        }
        if (!excludeFallback) {
            addAlternative(alternatives, fallbackLabel, negatedSoql);
        }
        Map<String, String> predicates = new Map<String, String>();
        for (String bucketLabel : alternatives.keySet()) {
            List<String> options = alternatives.get(bucketLabel);
            predicates.put(bucketLabel, options.size() == 1 ? options[0] : '(' + String.join(options, ') OR (') + ')');
        }
        return predicates;
    }

    /**
     * `SOQL` for "`node` does not match" with the in-memory semantics: AND / OR negate by De Morgan; a predicate flips
     * its operator (`NOT (...)` for `LIKE` and relative dates) and states the empty-field case explicitly, so a row
     * whose field is empty lands in the same bucket in `SOQL` as in `labelOf`.
     */
    private static String negate(BoardCondition.Node node, BoardCondition.Binder binder) {
        if (node instanceof BoardCondition.Junction) {
            BoardCondition.Junction junction = (BoardCondition.Junction) node;
            List<String> negated = new List<String>();
            for (BoardCondition.Node child : junction.children) {
                negated.add(negate(child, binder));
            }
            if (negated.size() == 1) {
                return negated[0];
            }
            return '(' + String.join(negated, junction.logic == 'AND' ? ') OR (' : ') AND (') + ')';
        }
        BoardCondition.Predicate predicate = (BoardCondition.Predicate) node;
        String flipped = FLIPPED_OPERATORS.get(predicate.operator);
        String negated = flipped == null
            ? 'NOT (' + predicate.toSoql(binder) + ')'
            : BoardCondition.field(predicate.filterId, predicate.path, flipped, predicate.values).toSoql(binder);
        // Evaluated against an empty row, the predicate tells whether it matches a row whose field is empty.
        return predicate.evaluate(new Map<String, Object>())
            ? '(' + negated + ') AND (' + predicate.path + ' != null)'
            : '(' + negated + ') OR (' + predicate.path + ' = null)';
    }

    /**
     * The Bucket filter condition keeping the rows in any of `selectedLabels`' buckets (the filter `filterId`): bucket
     * `i` is `rule_i AND NOT(rule_1..i-1)`, OR'd across selections; the fallback is `NOT(every rule)`. A label the
     * Bucket field doesn't have (or an excluded fallback) keeps no rows. Rules must be compiled first.
     */
    public Selection selection(String filterId, Set<String> selectedLabels) {
        return new Selection(this, filterId, selectedLabels);
    }

    /** A Bucket filter as a condition node: `SOQL` from `predicates`, in memory from `labelOf`, so both agree. */
    public class Selection extends BoardCondition.Node {
        public BoardBucketField bucketField;
        public String filterId;
        public Set<String> selectedLabels;

        public Selection(BoardBucketField bucketField, String filterId, Set<String> selectedLabels) {
            this.bucketField = bucketField;
            this.filterId = filterId;
            this.selectedLabels = selectedLabels == null ? new Set<String>() : selectedLabels;
        }

        /** The selected labels the Bucket field has, in bucket order. */
        public List<String> labels() {
            List<String> ordered = new List<String>();
            for (String bucketLabel : bucketField.labels()) {
                if (selectedLabels.contains(bucketLabel)) {
                    ordered.add(bucketLabel);
                }
            }
            return ordered;
        }

        public override String toSoql(BoardCondition.Binder binder) {
            List<String> ordered = labels();
            if (ordered.isEmpty()) {
                // No bucket selected that the Bucket field has: no row matches.
                return 'Id = null';
            }
            Map<String, String> bucketPredicates = bucketField.predicates(binder);
            List<String> options = new List<String>();
            for (String bucketLabel : ordered) {
                options.add(bucketPredicates.get(bucketLabel));
            }
            return options.size() == 1 ? options[0] : '(' + String.join(options, ') OR (') + ')';
        }

        public override Boolean evaluate(Map<String, Object> row) {
            String bucketLabel = bucketField.labelOf(row);
            return bucketLabel != null && selectedLabels.contains(bucketLabel);
        }
    }

    private static void addAlternative(Map<String, List<String>> alternatives, String bucketLabel, List<String> parts) {
        if (!alternatives.containsKey(bucketLabel)) {
            alternatives.put(bucketLabel, new List<String>());
        }
        alternatives.get(bucketLabel).add('(' + String.join(parts, ') AND (') + ')');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------------------------------------------------

    /** The Bucket field id a group or series field references (`bucket:<id>`), or null for a plain field path. */
    public static String referencedId(String fieldReference) {
        if (fieldReference == null || !fieldReference.trim().startsWithIgnoreCase(REFERENCE_PREFIX)) {
            return null;
        }
        return fieldReference.trim().substring(REFERENCE_PREFIX.length()).trim();
    }

    /** The Bucket field `id` among a Widget's `bucketFields` configs, parsed; a config error when there is none. */
    public static BoardBucketField find(List<Object> rawBucketFields, String id) {
        return find(rawBucketFields, null, id);
    }

    /**
     * The Bucket field `id` among a Widget's own `bucketFields` configs, else among the Board-level ones its Board's
     * Filter widget defines (`boardBucketFields`), parsed; a config error when neither has it.
     */
    public static BoardBucketField find(List<Object> widgetBucketFields, List<Object> boardBucketFields, String id) {
        Object raw = configWithId(widgetBucketFields, id);
        if (raw == null) {
            raw = configWithId(boardBucketFields, id);
        }
        if (raw == null) {
            throw configError(
                'Unknown Bucket field "' +
                    id +
                    '". Define it in the Widget\'s Bucket fields or in the Board\'s Filter widget.',
                id
            );
        }
        return fromConfig(raw);
    }

    private static Object configWithId(List<Object> rawBucketFields, String id) {
        if (rawBucketFields != null && id != null) {
            for (Object raw : rawBucketFields) {
                if (raw instanceof Map<String, Object> && id.equals(text(((Map<String, Object>) raw).get('id')))) {
                    return raw;
                }
            }
        }
        return null;
    }

    /** Parses and validates one Bucket field config (rule conditions stay raw until a query scope compiles them). */
    public static BoardBucketField fromConfig(Object raw) {
        if (!(raw instanceof Map<String, Object>)) {
            throw configError('Each Bucket field must be an object.', null);
        }
        Map<String, Object> source = (Map<String, Object>) raw;
        String id = text(source.get('id'));
        if (id == null) {
            throw configError('A Bucket field needs an id.', null);
        }
        String label = text(source.get('label'));
        Object rawRules = source.get('rules');
        List<Object> ruleConfigs = rawRules instanceof List<Object> ? (List<Object>) rawRules : new List<Object>();
        if (ruleConfigs.isEmpty()) {
            throw configError('Bucket field "' + displayName(id, label) + '" needs at least one rule.', id);
        }
        if (ruleConfigs.size() > MAX_RULES) {
            throw configError(
                'Bucket field "' +
                    displayName(id, label) +
                    '" has ' +
                    ruleConfigs.size() +
                    ' rules; at most ' +
                    MAX_RULES +
                    ' are allowed.',
                id
            );
        }
        List<Rule> rules = new List<Rule>();
        for (Integer i = 0; i < ruleConfigs.size(); i++) {
            rules.add(parseRule(ruleConfigs[i], i, displayName(id, label), id));
        }
        String fallbackLabel;
        Boolean exclude = false;
        if (source.get('fallback') instanceof Map<String, Object>) {
            Map<String, Object> fallback = (Map<String, Object>) source.get('fallback');
            fallbackLabel = text(fallback.get('label'));
            exclude = fallback.get('exclude') == true;
        }
        return new BoardBucketField(id, label, rules, fallbackLabel, exclude);
    }

    /** The error a formula field gets as a category or series field: it can't be grouped, a Bucket field can. */
    public static String formulaGroupingMessage(String fieldPath) {
        return 'Formula fields can\'t be used to group or split a chart (' +
            fieldPath +
            '). Define a Bucket field with the same logic instead; its rules can reference a formula checkbox.';
    }

    private static Rule parseRule(Object raw, Integer index, String bucketName, String id) {
        String position = 'Rule ' + (index + 1) + ' of Bucket field "' + bucketName + '"';
        if (!(raw instanceof Map<String, Object>)) {
            throw configError(position + ' must be an object.', id);
        }
        Map<String, Object> source = (Map<String, Object>) raw;
        String ruleLabel = text(source.get('label'));
        if (ruleLabel == null) {
            throw configError(position + ' needs a label.', id);
        }
        Object condition = source.get('condition');
        if (!(condition instanceof Map<String, Object>) || !hasConditions((Map<String, Object>) condition)) {
            throw configError(position + ' ("' + ruleLabel + '") has no conditions.', id);
        }
        Rule rule = new Rule(ruleLabel, null);
        rule.colour = text(source.get('colour'));
        rule.rawCondition = condition;
        return rule;
    }

    /** A single condition, or a group with at least one condition. */
    private static Boolean hasConditions(Map<String, Object> condition) {
        if (!condition.containsKey('conditions')) {
            return true;
        }
        Object children = condition.get('conditions');
        return children instanceof List<Object> && !((List<Object>) children).isEmpty();
    }

    private static String displayName(String id, String label) {
        return label == null ? id : label;
    }

    private static String text(Object value) {
        return value == null || String.isBlank(String.valueOf(value)) ? null : String.valueOf(value).trim();
    }

    private static BoardErrors.BoardException configError(String message, String id) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, id == null ? null : REFERENCE_PREFIX + id);
    }
}