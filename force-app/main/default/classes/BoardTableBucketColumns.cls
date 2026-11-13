/**
 * Bucket field columns of a Table widget: a column whose `fieldPath` is `bucket:<id>` shows, for each fetched record,
 * the label of the Bucket field `<id>` (defined in the request's `bucketFields`, see `BoardBucketField`), evaluated in
 * memory per row and stored in `TableRow.values` under the column's `fieldPath` (null when the Bucket field excludes
 * leftovers). The fields the rules read are fetched with each row (`TableColumn.fetchPaths`) but are no column. The
 * column is not sortable: sorting would need the bucket in `SOQL`.
 *
 * Rules on currency amounts compare corporate amounts, like `SOQL` (and the Bucket rule's amount, see
 * `BoardCurrencyConverter.IsoAmount`): each rule amount is read from the row in the record's currency (its
 * `CurrencyIsoCode` is fetched too) or, when it is also a converted currency column, in the Display currency.
 */
public with sharing class BoardTableBucketColumns {
    /** `dataType` of a Bucket field column: its cells are text labels. */
    public static final String COLUMN_DATA_TYPE = 'STRING';

    private final List<String> columnPaths = new List<String>();
    private final List<BoardBucketField> bucketFields = new List<BoardBucketField>();
    /** Parallel to `bucketFields`: how each rule path's row value becomes a corporate amount. */
    private final List<RuleCurrency> ruleCurrencies = new List<RuleCurrency>();

    /** Currency rule paths of one Bucket field (lower case) and where their row values are read from. */
    private class RuleCurrency {
        /** Rule path → the `CurrencyIsoCode` path of the record that owns it. */
        final Map<String, String> isoPaths = new Map<String, String>();
        /** Rule path → the Display currency its cell was converted to (it is also a currency column). */
        final Map<String, String> displayIsoCodes = new Map<String, String>();

        /** The row's value at `path`, a currency amount in the corporate currency (other values unchanged). */
        Object corporateValue(String path, Map<String, Object> valuesByLowerPath) {
            String key = path.toLowerCase();
            Object value = valuesByLowerPath.get(key);
            String isoPath = isoPaths.get(key);
            if (value == null || isoPath == null) {
                return value;
            }
            BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
            Decimal amount = Decimal.valueOf(String.valueOf(value));
            String displayIsoCode = displayIsoCodes.get(key);
            if (displayIsoCode != null) {
                return converter.convert(amount, displayIsoCode, converter.getCorporateIsoCode());
            }
            String recordIsoCode = (String) valuesByLowerPath.get(isoPath.toLowerCase());
            return recordIsoCode == null ? value : converter.toCorporate(amount, recordIsoCode);
        }
    }

    /** Whether a raw column config references a Bucket field (`fieldPath: 'bucket:<id>'`). */
    public static Boolean isBucketColumn(Map<String, Object> config) {
        return BoardBucketField.referencedId(BoardQueryService.getString(config, 'fieldPath')) != null;
    }

    /** A Bucket field column as configured; `resolve` gives it the Bucket field's label and the paths to fetch. */
    public static BoardQueryService.TableColumn column(Map<String, Object> config) {
        String bucketId = BoardBucketField.referencedId(BoardQueryService.getString(config, 'fieldPath'));
        BoardQueryService.TableColumn bucketColumn = new BoardQueryService.TableColumn();
        bucketColumn.fieldPath = BoardBucketField.REFERENCE_PREFIX + bucketId;
        String columnId = BoardQueryService.getString(config, 'id');
        bucketColumn.id = String.isBlank(columnId) ? bucketColumn.fieldPath : columnId;
        bucketColumn.label = bucketId;
        bucketColumn.dataType = COLUMN_DATA_TYPE;
        bucketColumn.isSortable = false;
        bucketColumn.isNameField = false;
        return bucketColumn;
    }

    /**
     * The Bucket field columns among `columns`: each one's Bucket field is found in the request's `bucketFields` and
     * its rules compiled against `scope` (the Widget's object and its parents only); the column gets the Bucket
     * field's label and fetches the fields its rules read. Empty when the Table has no Bucket field column.
     */
    public static BoardTableBucketColumns resolve(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        List<BoardQueryService.TableColumn> columns
    ) {
        BoardTableBucketColumns resolved = new BoardTableBucketColumns();
        for (BoardQueryService.TableColumn column : columns) {
            String bucketId = BoardBucketField.referencedId(column.fieldPath);
            if (bucketId == null) {
                continue;
            }
            BoardBucketField bucketField = BoardBucketField.find(
                BoardQueryService.getList(request, 'bucketFields'),
                BoardQueryService.getList(request, 'boardBucketFields'),
                bucketId
            );
            // Rules are evaluated in memory only: keep their bind values out of the Table query.
            Map<String, Object> bindsBefore = scope.binds.clone();
            scope.compileBucketRules(bucketField);
            scope.binds.clear();
            scope.binds.putAll(bindsBefore);
            if (String.isNotBlank(bucketField.label)) {
                column.label = bucketField.label;
            }
            column.fetchPaths = rulePaths(bucketField);
            resolved.ruleCurrencies.add(ruleCurrency(scope, columns, column.fetchPaths));
            resolved.columnPaths.add(column.fieldPath);
            resolved.bucketFields.add(bucketField);
        }
        return resolved;
    }

    /**
     * The currency rule paths among `rulePaths` (multi-currency orgs only), each one's `CurrencyIsoCode` path added
     * to `rulePaths` so it is fetched with the row.
     */
    private static RuleCurrency ruleCurrency(
        BoardQueryService.QueryScope scope,
        List<BoardQueryService.TableColumn> columns,
        List<String> rulePaths
    ) {
        RuleCurrency ruleCurrency = new RuleCurrency();
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        for (String path : new List<String>(rulePaths)) {
            BoardQueryService.ResolvedField field = BoardQueryService.resolveFieldPath(
                scope.objectDescribe,
                path,
                null,
                path
            );
            String isoPath = converter.isoCodePath(field.path, field.type);
            if (isoPath == null) {
                continue;
            }
            ruleCurrency.isoPaths.put(path.toLowerCase(), isoPath);
            rulePaths.add(isoPath);
            for (BoardQueryService.TableColumn column : columns) {
                if (
                    column.fetchPaths == null &&
                    column.currencyIsoCode != null &&
                    path.equalsIgnoreCase(column.fieldPath)
                ) {
                    ruleCurrency.displayIsoCodes.put(path.toLowerCase(), column.currencyIsoCode);
                }
            }
        }
        return ruleCurrency;
    }

    /** Puts each row's bucket label of every Bucket field column into `row.values` under the column's `fieldPath`. */
    public void labelRows(List<BoardQueryService.TableRow> rows) {
        if (bucketFields.isEmpty() || rows == null) {
            return;
        }
        for (BoardQueryService.TableRow row : rows) {
            Map<String, Object> valuesByLowerPath = new Map<String, Object>();
            for (String path : row.values.keySet()) {
                valuesByLowerPath.put(path.toLowerCase(), row.values.get(path));
            }
            for (Integer i = 0; i < bucketFields.size(); i++) {
                row.values.put(columnPaths[i], bucketFields[i].labelOf(ruleRow(valuesByLowerPath, i)));
            }
        }
    }

    /** The values the rules of Bucket field `index` read, keyed by their exact rule paths. */
    private Map<String, Object> ruleRow(Map<String, Object> valuesByLowerPath, Integer index) {
        Map<String, Object> ruleValues = new Map<String, Object>();
        for (BoardBucketField.Rule rule : bucketFields[index].rules) {
            for (String path : conditionPaths(rule.condition)) {
                ruleValues.put(path, ruleCurrencies[index].corporateValue(path, valuesByLowerPath));
            }
        }
        return ruleValues;
    }

    /** Every field path the compiled rules of `bucketField` read, once each (case-insensitively), in rule order. */
    private static List<String> rulePaths(BoardBucketField bucketField) {
        List<String> paths = new List<String>();
        Set<String> seen = new Set<String>();
        for (BoardBucketField.Rule rule : bucketField.rules) {
            for (String path : conditionPaths(rule.condition)) {
                if (seen.add(path.toLowerCase())) {
                    paths.add(path);
                }
            }
        }
        return paths;
    }

    private static List<String> conditionPaths(BoardCondition.Node node) {
        List<String> paths = new List<String>();
        if (node instanceof BoardCondition.Junction) {
            for (BoardCondition.Node child : ((BoardCondition.Junction) node).children) {
                paths.addAll(conditionPaths(child));
            }
        } else if (node instanceof BoardCondition.Predicate) {
            paths.add(((BoardCondition.Predicate) node).path);
        }
        return paths;
    }
}