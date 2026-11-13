/**
 * Entry-point tests of Base filters combined with AND / OR groups (`{ id, logic, conditions[] }` entries in
 * `baseFilters`, alongside plain conditions that combine with AND).
 *
 * Opportunities: Small 100, Mid 250, Large 500, Blank (no amount). All in the same stage, closing today.
 */
@IsTest
private class BoardQueryServiceBaseFilterTest {
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Board Base Filter Account');
        insert account;
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        List<Opportunity> opportunities = new List<Opportunity>();
        Map<String, Decimal> amounts = new Map<String, Decimal>{
            'Small' => 100,
            'Mid' => 250,
            'Large' => 500,
            'Blank' => null
        };
        for (String name : amounts.keySet()) {
            opportunities.add(
                new Opportunity(
                    Name = 'BF ' + name,
                    AccountId = account.Id,
                    StageName = stage,
                    CloseDate = Date.today(),
                    Amount = amounts.get(name)
                )
            );
        }
        insert opportunities;
    }

    @IsTest
    static void orGroupKeepsRowsMatchingAnyCondition() {
        Map<String, Object> request = metricRequest('COUNT', null);
        addBaseFilter(
            request,
            orGroup(
                'g1',
                new List<Object>{
                    condition('large', 'Amount', 'GTE', 500),
                    condition('blank', 'Amount', 'IS_NULL', true)
                }
            )
        );

        Assert.areEqual(2, run(request).value, 'Large and Blank');
        Assert.areEqual(
            500,
            (Decimal) run(withAggregate(request, 'SUM', 'Amount')).value,
            'SUM over the same scope: Large only has an amount'
        );
    }

    @IsTest
    static void groupsNestAndCombineWithPlainConditionsUsingAnd() {
        // Name LIKE 'BF%' AND (Amount < 200 OR (Amount >= 200 AND Name LIKE '%Large'))
        Map<String, Object> request = metricRequest('COUNT', null);
        addBaseFilter(request, condition('prefix', 'Name', 'LIKE', 'BF%'));
        addBaseFilter(
            request,
            orGroup(
                'g1',
                new List<Object>{
                    condition('small', 'Amount', 'LT', 200),
                    conditionGroup(
                        'g2',
                        'AND',
                        new List<Object>{
                            condition('big', 'Amount', 'GTE', 200),
                            condition('large', 'Name', 'LIKE', '%Large')
                        }
                    )
                }
            )
        );

        Assert.areEqual(2, run(request).value, 'Small and Large; Mid fails the inner AND, Blank has no amount');
    }

    @IsTest
    static void anAndGroupBehavesLikeTheSameConditionsListedFlat() {
        Map<String, Object> grouped = metricRequest('COUNT', null);
        addBaseFilter(
            grouped,
            conditionGroup(
                'g1',
                'and',
                new List<Object>{ condition('min', 'Amount', 'GTE', 100), condition('max', 'Amount', 'LT', 500) }
            )
        );
        Map<String, Object> flat = metricRequest('COUNT', null);
        addBaseFilter(flat, condition('min', 'Amount', 'GTE', 100));
        addBaseFilter(flat, condition('max', 'Amount', 'LT', 500));

        Assert.areEqual(2, run(grouped).value, 'Small and Mid');
        Assert.areEqual(run(flat).value, run(grouped).value);
    }

    @IsTest
    static void orGroupsCombineWithBoardFilterContextUsingAnd() {
        Map<String, Object> request = metricRequest('COUNT', null);
        Map<String, Object> filledAmount = new Map<String, Object>{
            'filterId' => 'filled',
            'type' => 'EMPTY_FILLED',
            'fieldPath' => 'Amount',
            'explicit' => true,
            'operator' => 'FILLED',
            'values' => new List<Object>()
        };
        ((List<Object>) request.get('filters')).add(filledAmount);
        addBaseFilter(
            request,
            orGroup(
                'g1',
                new List<Object>{
                    condition('large', 'Amount', 'GTE', 500),
                    condition('blank', 'Amount', 'IS_NULL', true)
                }
            )
        );

        Assert.areEqual(1, run(request).value, 'Large only: Blank fails the Filled in filter');
    }

    @IsTest
    static void invalidGroupsAreConfigErrorsNamingTheGroupOrCondition() {
        assertConfigError(orGroup('empty', new List<Object>()), 'empty');
        assertConfigError(
            conditionGroup('xor', 'XOR', new List<Object>{ condition('min', 'Amount', 'GTE', 100) }),
            'xor'
        );
        assertConfigError(
            orGroup(
                'g1',
                new List<Object>{ condition('min', 'Amount', 'GTE', 100), condition('noField', '', 'EQ', 1) }
            ),
            'noField'
        );
        // `SOQL` can't combine semi-joins with OR, so child relationship conditions stay out of OR groups.
        assertConfigError(
            orGroup(
                'g1',
                new List<Object>{
                    condition('min', 'Amount', 'GTE', 100),
                    conditionGroup(
                        'g2',
                        'AND',
                        new List<Object>{ condition('lines', 'OpportunityLineItem(OpportunityId).Quantity', 'GT', 1) }
                    )
                }
            ),
            'lines'
        );
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> metricRequest(String aggregateFunction, String valueField) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => aggregateFunction,
            'valueFieldApiName' => valueField,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
    }

    private static Map<String, Object> withAggregate(
        Map<String, Object> request,
        String aggregateFunction,
        String valueField
    ) {
        Map<String, Object> copy = new Map<String, Object>(request);
        copy.put('aggregateFunction', aggregateFunction);
        copy.put('valueFieldApiName', valueField);
        return copy;
    }

    private static Map<String, Object> condition(String id, String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'id' => id,
            'fieldPath' => fieldPath,
            'operator' => operator,
            'value' => value
        };
    }

    private static Map<String, Object> conditionGroup(String id, String logic, List<Object> conditions) {
        return new Map<String, Object>{ 'id' => id, 'logic' => logic, 'conditions' => conditions };
    }

    private static Map<String, Object> orGroup(String id, List<Object> conditions) {
        return conditionGroup(id, 'OR', conditions);
    }

    private static void addBaseFilter(Map<String, Object> request, Map<String, Object> entry) {
        ((List<Object>) request.get('baseFilters')).add(entry);
    }

    private static BoardQueryService.MetricResult run(Map<String, Object> request) {
        return BoardQueryService.queryMetric(JSON.serialize(request));
    }

    private static void assertConfigError(Map<String, Object> entry, String filterId) {
        Map<String, Object> request = metricRequest('COUNT', null);
        addBaseFilter(request, entry);
        String requestJson = JSON.serialize(request);
        try {
            BoardQueryService.queryMetric(requestJson);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            Assert.areEqual(filterId, payload.get('filterId'), String.valueOf(payload));
            return;
        }
        Assert.fail('Expected CONFIG_ERROR for ' + requestJson);
    }
}