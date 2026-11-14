/**
 * One group field of a Table's Row grouping (Detail rows on or off): its resolved path, group order, label source and
 * (for dates) bucketing, shared by the grouped record stream (`BoardTableGrouping`) and the aggregated table
 * (`BoardTableAggregate`).
 *
 * A level groups by a lookup (by record Id, labelled by the record name), picklist, text or date field, direct or
 * through a 1-5 hop parent path. Dates are bucketed by the Chart widget's granularities (`CALENDAR_MONTH` etc.): the
 * `GROUP BY` expressions bucket them in SOQL (`keyOf` reads the bucket key back), and `keyRow` buckets a record's value
 * in memory under the level's `keyPath`, with the same keys (`2026-03`, `2026-Q1`, `FY2026-Q2`) and labels.
 */
public with sharing class BoardTableGroupLevel {
    /** Non-date field types a Table can group by. */
    private static final Set<Schema.DisplayType> GROUP_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.REFERENCE,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.COMBOBOX,
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL
    };
    private static final Set<Schema.DisplayType> DATE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };
    /** Date granularities shared with the Chart widget. */
    private static final Set<String> DATE_GRANULARITIES = new Set<String>{
        'DAY',
        'CALENDAR_MONTH',
        'CALENDAR_QUARTER',
        'CALENDAR_YEAR',
        'FISCAL_QUARTER',
        'FISCAL_YEAR'
    };
    private static final String GROUP_KEYS_BIND = 'tableGroupKeys';
    private static final String GROUP_FROM_BIND = 'tableGroupFrom';
    private static final String GROUP_TO_BIND = 'tableGroupTo';
    private static Organization fiscalSettings;

    public BoardTableGrouping.GroupField field = new BoardTableGrouping.GroupField();
    public Boolean isLookup = false;
    public Boolean isDateTime = false;
    /** Date bucket granularity; null for non-date levels. */
    public String granularity;
    /** Alias prefix of this level's `GROUP BY` columns (`g1`, `g2`). */
    public String alias;
    /** Lower-cased path prefix of fields reached through a lookup group field (e.g. `account.`), else null. */
    public String relationshipPrefix;
    private Map<String, String> picklistLabels = new Map<String, String>();
    /** Date bucket labels by bucket key, collected as rows are keyed. */
    private Map<String, String> bucketLabels = new Map<String, String>();
    /** `GROUP BY` expressions and their aliases. */
    public List<String> expressions = new List<String>();
    private List<String> aliases = new List<String>();

    public BoardTableGroupLevel(Schema.DescribeSObjectResult objectDescribe, Map<String, Object> entry, Integer level) {
        String rawPath = BoardQueryService.getString(entry, 'fieldPath');
        if (String.isBlank(rawPath)) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Choose a group field.', null, 'groupBy');
        }
        BoardQueryService.ResolvedField resolved = BoardTableQuery.resolveTablePath(objectDescribe, rawPath);
        alias = 'g' + level;
        field.fieldPath = resolved.path;
        field.keyPath = resolved.path;
        field.label = resolved.describe.getLabel();
        field.dataType = resolved.type.name();
        field.sortDirection = 'DESC'.equalsIgnoreCase(BoardQueryService.getString(entry, 'sortDirection'))
            ? 'DESC'
            : 'ASC';
        resolveGranularity(resolved, rawPath, BoardQueryService.getString(entry, 'dateGranularity'), level);
        if (granularity == null) {
            if (!GROUP_TYPES.contains(resolved.type) || !resolved.describe.isGroupable()) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A Table can group by a lookup, picklist, text or date field: ' + rawPath,
                    null,
                    rawPath
                );
            }
            expressions.add(resolved.path);
            aliases.add(alias + 'k');
        }
        isLookup = resolved.type == Schema.DisplayType.REFERENCE;
        if (isLookup) {
            field.labelPath = nameFieldPath(resolved);
            String lookupPath = relationshipPath(resolved);
            relationshipPrefix = lookupPath == null ? null : lookupPath.toLowerCase() + '.';
        }
        if (resolved.type == Schema.DisplayType.PICKLIST || resolved.type == Schema.DisplayType.COMBOBOX) {
            for (Schema.PicklistEntry picklistEntry : resolved.describe.getPicklistValues()) {
                picklistLabels.put(picklistEntry.getValue(), picklistEntry.getLabel());
            }
        }
        resolveOrderBy(objectDescribe, resolved, BoardQueryService.getString(entry, 'orderBy'));
    }

    /** `Relationship.NameField` of a lookup's target (e.g. `Opportunity.Name`), or null when unreadable. */
    private static String nameFieldPath(BoardQueryService.ResolvedField reference) {
        String relationshipPath = relationshipPath(reference);
        if (relationshipPath == null) {
            return null;
        }
        Schema.DescribeSObjectResult target = BoardDescribe.describeObject(
            BoardQueryService.parentType(reference.describe)
        );
        if (!BoardDescribe.isReadableObject(target)) {
            return null;
        }
        String nameField = BoardDescribe.readableNameField(target);
        return nameField == null ? null : relationshipPath + '.' + nameField;
    }

    /** Relationship path of a lookup (`OpportunityId` -> `Opportunity`, `Account.ParentId` -> `Account.Parent`). */
    private static String relationshipPath(BoardQueryService.ResolvedField reference) {
        String relationshipName = reference.describe.getRelationshipName();
        if (relationshipName == null) {
            return null;
        }
        List<String> segments = reference.path.split('\\.');
        segments[segments.size() - 1] = relationshipName;
        return String.join(segments, '.');
    }

    private static Organization getFiscalSettings() {
        if (fiscalSettings == null) {
            fiscalSettings = [
                SELECT FiscalYearStartMonth, UsesStartDateAsFiscalYearName
                FROM Organization
                LIMIT 1
            ];
        }
        return fiscalSettings;
    }

    private void resolveGranularity(
        BoardQueryService.ResolvedField resolved,
        String rawPath,
        String rawGranularity,
        Integer level
    ) {
        String requested = String.isBlank(rawGranularity) ? null : rawGranularity.trim().toUpperCase();
        Boolean isDate = DATE_TYPES.contains(resolved.type);
        if (requested != null && !DATE_GRANULARITIES.contains(requested)) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Unsupported date granularity: ' + rawGranularity,
                null,
                rawPath
            );
        }
        if (requested != null && !isDate) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Date granularity requires a Date or DateTime field: ' + rawPath,
                null,
                rawPath
            );
        }
        if (!isDate) {
            return;
        }
        granularity = requested == null ? 'DAY' : requested;
        isDateTime = resolved.type == Schema.DisplayType.DATETIME;
        field.dateGranularity = granularity;
        field.keyPath = 'groupKey' + level;
        String source = isDateTime ? 'convertTimezone(' + resolved.path + ')' : resolved.path;
        switch on granularity {
            when 'DAY' {
                addExpression(isDateTime ? 'DAY_ONLY(' + source + ')' : resolved.path, 'k');
            }
            when 'CALENDAR_MONTH' {
                addExpression('CALENDAR_YEAR(' + source + ')', 'y');
                addExpression('CALENDAR_MONTH(' + source + ')', 'p');
            }
            when 'CALENDAR_QUARTER' {
                addExpression('CALENDAR_YEAR(' + source + ')', 'y');
                addExpression('CALENDAR_QUARTER(' + source + ')', 'p');
            }
            when 'CALENDAR_YEAR' {
                addExpression('CALENDAR_YEAR(' + source + ')', 'y');
            }
            when 'FISCAL_QUARTER' {
                addExpression('FISCAL_YEAR(' + source + ')', 'y');
                addExpression('FISCAL_QUARTER(' + source + ')', 'p');
            }
            when else {
                addExpression('FISCAL_YEAR(' + source + ')', 'y');
            }
        }
    }

    private void addExpression(String expression, String suffix) {
        expressions.add(expression);
        aliases.add(alias + suffix);
    }

    /** Group order by a field constant per group: a field of the lookup group field's record. */
    private void resolveOrderBy(
        Schema.DescribeSObjectResult objectDescribe,
        BoardQueryService.ResolvedField resolved,
        String rawOrderBy
    ) {
        if (String.isBlank(rawOrderBy)) {
            return;
        }
        String prefix = isLookup ? relationshipPath(resolved) : null;
        BoardQueryService.ResolvedField orderField = BoardTableQuery.resolveTablePath(objectDescribe, rawOrderBy);
        if (prefix == null || !orderField.path.startsWithIgnoreCase(prefix + '.')) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Order groups by a field of the lookup group field\'s record (e.g. Opportunity.Amount): ' + rawOrderBy,
                null,
                rawOrderBy
            );
        }
        if (!orderField.describe.isSortable()) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Field is not sortable: ' + rawOrderBy, null, rawOrderBy);
        }
        field.orderBy = orderField.path;
    }

    /** `ORDER BY` paths of this level: order field, lookup record name, group field (dates by their raw value). */
    public List<String> orderPaths() {
        List<String> paths = new List<String>();
        for (String path : new List<String>{ field.orderBy, field.labelPath, field.fieldPath }) {
            if (path != null) {
                paths.add(path);
            }
        }
        return paths;
    }

    /**
     * True when a field has one value per group of this level: the (non-date) group field itself or a field reached
     * through the lookup group field.
     */
    public Boolean isConstantPerGroup(String path) {
        String lowerPath = path.toLowerCase();
        return (granularity == null && lowerPath == field.fieldPath.toLowerCase()) ||
            (relationshipPrefix != null && lowerPath.startsWith(relationshipPrefix));
    }

    /**
     * A parent path (e.g. `Account.CreatedDate`). For a record whose parent is missing the platform evaluates the
     * parent's fields to placeholder values in `WHERE`, `GROUP BY` and `ORDER BY` (a date, not null), though the
     * selected value is null; such records are told apart on the relationship Id at each hop.
     */
    public Boolean isParentPath() {
        return field.fieldPath.contains('.');
    }

    /** `Id` path of each relationship hop (`Account.Owner.Name` -> `Account.Id`, `Account.Owner.Id`). */
    private List<String> parentIdPaths() {
        List<String> segments = field.fieldPath.split('\\.');
        List<String> paths = new List<String>();
        for (Integer hop = 1; hop < segments.size(); hop++) {
            List<String> relationship = new List<String>();
            for (Integer i = 0; i < hop; i++) {
                relationship.add(segments[i]);
            }
            paths.add(String.join(relationship, '.') + '.Id');
        }
        return paths;
    }

    /** Records of this level's "(Blank)" group: a missing parent at any hop, or no value. */
    public String blankPredicate() {
        List<String> predicates = new List<String>();
        for (String idPath : parentIdPaths()) {
            predicates.add(idPath + ' = null');
        }
        predicates.add(field.fieldPath + ' = null');
        return '(' + String.join(predicates, ' OR ') + ')';
    }

    /** Records of this level's non-blank groups: every parent present, and a value. */
    public String valuePredicate() {
        List<String> predicates = new List<String>();
        for (String idPath : parentIdPaths()) {
            predicates.add(idPath + ' != null');
        }
        predicates.add(field.fieldPath + ' != null');
        return '(' + String.join(predicates, ' AND ') + ')';
    }

    /** Whether a loaded row falls in this level's "(Blank)" group. */
    public Boolean hasBlankRow(List<Map<String, Object>> rows) {
        for (Map<String, Object> row : rows) {
            Object key = row.get(field.keyPath);
            if (key == null || String.isBlank(String.valueOf(key))) {
                return true;
            }
        }
        return false;
    }

    /** `expression alias` of each `GROUP BY` expression of this level. */
    public List<String> selectColumns() {
        List<String> columns = new List<String>();
        for (Integer i = 0; i < expressions.size(); i++) {
            columns.add(expressions[i] + ' ' + aliases[i]);
        }
        return columns;
    }

    /** Writes a date row's bucket key under `keyPath` (other levels key rows by the group field itself). */
    public void keyRow(Map<String, Object> row) {
        if (granularity == null) {
            return;
        }
        Date day = dayOf(row.get(field.fieldPath));
        if (day == null) {
            row.put(field.keyPath, null);
            return;
        }
        List<String> bucket = bucketOf(day);
        bucketLabels.put(bucket[0], bucket[1]);
        row.put(field.keyPath, bucket[0]);
    }

    /** Local calendar date of a Date or DateTime value (DateTimes in the user's time zone, as `convertTimezone`). */
    private Date dayOf(Object raw) {
        if (raw == null) {
            return null;
        }
        return isDateTime ? ((Datetime) raw).date() : (Date) raw;
    }

    /** Group key of an aggregate row (as `keyRow` writes it for a record); null for blanks. */
    public String keyOf(AggregateResult aggregate) {
        if (granularity == null) {
            Object raw = aggregate.get(alias + 'k');
            return raw == null ? null : String.valueOf(raw);
        }
        if (granularity == 'DAY') {
            Date day = (Date) aggregate.get(alias + 'k');
            return day == null ? null : String.valueOf(day);
        }
        Integer year = (Integer) aggregate.get(alias + 'y');
        Integer period = aliases.size() > 1 ? (Integer) aggregate.get(alias + 'p') : null;
        return year == null ? null : bucketKey(year, period);
    }

    /** Raw group value of an aggregate row: the grouped value itself, or a date level's bucket key. */
    public Object rawKeyOf(AggregateResult aggregate) {
        return granularity == null ? aggregate.get(alias + 'k') : keyOf(aggregate);
    }

    /** Count key: text groups match case-insensitively, as `GROUP BY` folds case; blanks under `''`. */
    public String countKey(String key) {
        if (String.isBlank(key)) {
            return '';
        }
        return isLookup || granularity != null ? key : key.toLowerCase();
    }

    /** Sets a group's full-group count, lookup link and display label (picklist label, date bucket label). */
    public void decorate(BoardTableEngine.TableGroup tableGroup, Integer count) {
        tableGroup.count = count == null ? 0 : count;
        if (tableGroup.key == null) {
            return;
        }
        if (isLookup) {
            tableGroup.recordId = tableGroup.key;
        }
        if (picklistLabels.containsKey(tableGroup.key)) {
            tableGroup.label = picklistLabels.get(tableGroup.key);
        }
        if (bucketLabels.containsKey(tableGroup.key)) {
            tableGroup.label = bucketLabels.get(tableGroup.key);
        }
    }

    /**
     * Display label of a non-blank group key: the picklist label, the date bucket label, the lookup record name
     * (`recordName`, from the group's values), else the key itself.
     */
    public String labelOf(String key, Object recordName) {
        if (picklistLabels.containsKey(key)) {
            return picklistLabels.get(key);
        }
        if (granularity != null) {
            return bucketLabelOf(key);
        }
        return recordName == null ? key : String.valueOf(recordName);
    }

    /**
     * `WHERE` predicate limiting a count query to `groups` of this (first) level: their keys, or for dates the range
     * from the first to the last bucket (the buckets are contiguous in the group order).
     */
    public String pageRestriction(List<BoardTableEngine.TableGroup> groups, Map<String, Object> binds) {
        List<String> predicates = new List<String>();
        Boolean hasBlank = false;
        List<Object> keys = isLookup ? (List<Object>) new List<Id>() : (List<Object>) new List<String>();
        Date firstDay;
        Date lastDay;
        for (BoardTableEngine.TableGroup tableGroup : groups) {
            if (tableGroup.key == null) {
                hasBlank = true;
            } else if (granularity != null) {
                Date day = bucketStart(tableGroup.key);
                firstDay = firstDay == null || day < firstDay ? day : firstDay;
                lastDay = lastDay == null || day > lastDay ? day : lastDay;
            } else {
                keys.add(isLookup ? (Object) Id.valueOf(tableGroup.key) : (Object) tableGroup.key);
            }
        }
        if (!keys.isEmpty()) {
            binds.put(GROUP_KEYS_BIND, keys);
            predicates.add(withValue(field.fieldPath + ' IN :' + GROUP_KEYS_BIND));
        }
        if (firstDay != null) {
            Date endDay = nextBucketStart(lastDay);
            binds.put(GROUP_FROM_BIND, isDateTime ? (Object) localMidnight(firstDay) : (Object) firstDay);
            binds.put(GROUP_TO_BIND, isDateTime ? (Object) localMidnight(endDay) : (Object) endDay);
            predicates.add(
                withValue(
                    '(' +
                        field.fieldPath +
                        ' >= :' +
                        GROUP_FROM_BIND +
                        ' AND ' +
                        field.fieldPath +
                        ' < :' +
                        GROUP_TO_BIND +
                        ')'
                )
            );
        }
        if (hasBlank) {
            predicates.add(isParentPath() ? blankPredicate() : field.fieldPath + ' = null');
        }
        return String.join(predicates, ' OR ');
    }

    /** A key predicate of a parent path also requires the parent (a missing one's placeholder could match). */
    private String withValue(String keyPredicate) {
        return isParentPath() ? '(' + keyPredicate + ' AND ' + valuePredicate() + ')' : keyPredicate;
    }

    private Datetime localMidnight(Date day) {
        return Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    }

    // ---- Date buckets (keys and labels as the Chart widget's: `2026-03`, `2026-Q1`, `FY2026-Q2`) --------------------

    /** `[key, label]` of the bucket holding `day`. */
    private List<String> bucketOf(Date day) {
        if (granularity == 'DAY') {
            return new List<String>{ String.valueOf(day), day.format() };
        }
        Integer period;
        Integer year = day.year();
        switch on granularity {
            when 'CALENDAR_MONTH' {
                period = day.month();
            }
            when 'CALENDAR_QUARTER' {
                period = (day.month() - 1) / 3 + 1;
            }
            when 'CALENDAR_YEAR' {
                period = null;
            }
            when else {
                year = fiscalYearName(day);
                period = granularity == 'FISCAL_QUARTER' ? fiscalQuarterIndex(day) + 1 : null;
            }
        }
        return new List<String>{ bucketKey(year, period), bucketLabel(year, period) };
    }

    private String bucketKey(Integer year, Integer period) {
        String yearText = String.valueOf(year);
        switch on granularity {
            when 'CALENDAR_MONTH' {
                return yearText + '-' + String.valueOf(period).leftPad(2, '0');
            }
            when 'CALENDAR_QUARTER' {
                return yearText + '-Q' + period;
            }
            when 'CALENDAR_YEAR' {
                return yearText;
            }
            when 'FISCAL_QUARTER' {
                return 'FY' + yearText + '-Q' + period;
            }
            when else {
                return 'FY' + yearText;
            }
        }
    }

    private String bucketLabel(Integer year, Integer period) {
        String yearText = String.valueOf(year);
        switch on granularity {
            when 'CALENDAR_MONTH' {
                return Datetime.newInstance(year, period, 1).format('MMM yyyy');
            }
            when 'CALENDAR_QUARTER' {
                return 'Q' + period + ' ' + yearText;
            }
            when 'CALENDAR_YEAR' {
                return yearText;
            }
            when 'FISCAL_QUARTER' {
                return 'Q' + period + ' FY' + yearText;
            }
            when else {
                return 'FY' + yearText;
            }
        }
    }

    /** Label of a bucket key (inverse of `bucketKey`, as `bucketOf` labels it). */
    private String bucketLabelOf(String key) {
        if (granularity == 'DAY') {
            return Date.valueOf(key).format();
        }
        String body = key.removeStart('FY');
        Integer year = Integer.valueOf(body.left(4));
        String periodText = body.length() > 4 ? body.substring(5).removeStart('Q') : null;
        return bucketLabel(year, periodText == null ? null : Integer.valueOf(periodText));
    }

    /** First day of the bucket a bucket key names (inverse of `bucketKey`). */
    private Date bucketStart(String key) {
        if (granularity == 'DAY') {
            return Date.valueOf(key);
        }
        String body = key.removeStart('FY');
        Integer year = Integer.valueOf(body.left(4));
        String periodText = body.length() > 4 ? body.substring(5).removeStart('Q') : null;
        Integer period = periodText == null ? null : Integer.valueOf(periodText);
        switch on granularity {
            when 'CALENDAR_MONTH' {
                return Date.newInstance(year, period, 1);
            }
            when 'CALENDAR_QUARTER' {
                return Date.newInstance(year, (period - 1) * 3 + 1, 1);
            }
            when 'CALENDAR_YEAR' {
                return Date.newInstance(year, 1, 1);
            }
            when else {
                Date fiscalStart = fiscalYearStartFor(year);
                return period == null ? fiscalStart : fiscalStart.addMonths((period - 1) * 3);
            }
        }
    }

    /** First day of the bucket after the one starting `start`. */
    private Date nextBucketStart(Date start) {
        switch on granularity {
            when 'DAY' {
                return start.addDays(1);
            }
            when 'CALENDAR_MONTH' {
                return start.addMonths(1);
            }
            when 'CALENDAR_QUARTER', 'FISCAL_QUARTER' {
                return start.addMonths(3);
            }
            when else {
                return start.addMonths(12);
            }
        }
    }

    private Integer fiscalStartMonth() {
        Organization settings = getFiscalSettings();
        return settings.FiscalYearStartMonth == null ? 1 : settings.FiscalYearStartMonth;
    }

    /** Whether a fiscal year is named by the calendar year it ends in (the default when it starts after January). */
    private Boolean namedByEndYear() {
        return fiscalStartMonth() != 1 && !getFiscalSettings().UsesStartDateAsFiscalYearName;
    }

    private Integer fiscalYearName(Date day) {
        Integer startYear = day.month() >= fiscalStartMonth() ? day.year() : day.year() - 1;
        return namedByEndYear() ? startYear + 1 : startYear;
    }

    private Integer fiscalQuarterIndex(Date day) {
        return Math.mod(day.month() - fiscalStartMonth() + 12, 12) / 3;
    }

    /** First day of the fiscal year named `fiscalYear`. */
    private Date fiscalYearStartFor(Integer fiscalYear) {
        Integer startYear = namedByEndYear() ? fiscalYear - 1 : fiscalYear;
        return Date.newInstance(startYear, fiscalStartMonth(), 1);
    }
}