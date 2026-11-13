/**
 * Engine-unit seam for Bucket fields: rule evaluation (first match wins, fallback, exclude) against in-memory rows,
 * the per-bucket `SOQL` predicates, and Bucket field config parsing. Pure: no DML, no queries.
 */
@IsTest
private class BoardBucketFieldTest {
    /** Numbers its binds `:p0`, `:p1`... so compiled predicates read predictably. */
    private class CountingBinder implements BoardCondition.Binder {
        Integer count = 0;

        public String bind(Object value, Boolean isLikePattern) {
            return ':p' + (count++);
        }
    }

    private static BoardCondition.Node amountAtLeast(Decimal amount) {
        return BoardCondition.field('r', 'Amount', 'GTE', new List<Object>{ amount });
    }

    private static BoardCondition.Node leadSourceIs(String leadSource) {
        return BoardCondition.field('r', 'LeadSource', 'EQ', new List<Object>{ leadSource });
    }

    /** Large (Amount >= 300), Medium (Amount >= 150), Web (LeadSource = 'web'), fallback as given. */
    private static BoardBucketField dealSize(String fallbackLabel, Boolean exclude) {
        return new BoardBucketField(
            'dealSize',
            'Deal size',
            new List<BoardBucketField.Rule>{
                new BoardBucketField.Rule('Large', amountAtLeast(300)),
                new BoardBucketField.Rule('Medium', amountAtLeast(150)),
                new BoardBucketField.Rule('Web', leadSourceIs('web'))
            },
            fallbackLabel,
            exclude
        );
    }

    private static Map<String, Object> row(Decimal amount, String leadSource) {
        return new Map<String, Object>{ 'Amount' => amount, 'LeadSource' => leadSource };
    }

    @IsTest
    static void firstMatchingRuleWins() {
        BoardBucketField bucketField = dealSize(null, false);

        Assert.areEqual('Large', bucketField.labelOf(row(350, 'Web')), 'Matches all three rules: the first wins');
        Assert.areEqual('Medium', bucketField.labelOf(row(200, 'Web')), 'Not Large: Medium comes before Web');
        Assert.areEqual('Web', bucketField.labelOf(row(100, 'WEB')), 'Text matches case-insensitively');
        Assert.areEqual('Web', bucketField.labelOf(row(null, 'Web')), 'A null Amount matches no range rule');
    }

    @IsTest
    static void rowsMatchingNoRuleGoToTheFallbackBucketOrAreExcluded() {
        Assert.areEqual('Other', dealSize(null, false).labelOf(row(100, 'Phone')), 'Fallback label defaults to Other');
        Assert.areEqual('Other', dealSize('  ', false).labelOf(row(null, null)), 'A blank fallback label is Other');
        Assert.areEqual('Small deals', dealSize('Small deals', false).labelOf(row(100, null)));
        Assert.isNull(dealSize('Small deals', true).labelOf(row(100, null)), 'Excluded rows get no bucket');
        Assert.areEqual('Large', dealSize('Small deals', true).labelOf(row(300, null)));
    }

    @IsTest
    static void pathsListEveryFieldTheRulesReadOnceInRuleOrder() {
        BoardBucketField bucketField = new BoardBucketField(
            'b',
            'B',
            new List<BoardBucketField.Rule>{
                new BoardBucketField.Rule('Big', amountAtLeast(300)),
                new BoardBucketField.Rule(
                    'Mixed',
                    BoardCondition.anyOf(
                        new List<BoardCondition.Node>{
                            leadSourceIs('Web'),
                            BoardCondition.field('r', 'Account.Name', 'EQ', new List<Object>{ 'Acme' }),
                            BoardCondition.field('r', 'Amount', 'LT', new List<Object>{ 10 })
                        }
                    )
                )
            },
            null,
            false
        );

        Assert.areEqual(new List<String>{ 'Amount', 'LeadSource', 'Account.Name' }, bucketField.paths());
    }

    @IsTest
    static void bucketLabelsFollowRuleOrderOnceEachThenTheFallback() {
        BoardBucketField bucketField = new BoardBucketField(
            'b',
            'B',
            new List<BoardBucketField.Rule>{
                new BoardBucketField.Rule('Big', amountAtLeast(300)),
                new BoardBucketField.Rule('Web', leadSourceIs('Web')),
                new BoardBucketField.Rule('Big', leadSourceIs('Partner'))
            },
            'Rest',
            false
        );

        Assert.areEqual(new List<String>{ 'Big', 'Web', 'Rest' }, bucketField.labels());
        Assert.areEqual('Big', bucketField.labelOf(row(10, 'Partner')), 'Rules sharing a label share one bucket');
        Assert.areEqual(new List<String>{ 'Large', 'Medium', 'Web' }, dealSize(null, true).labels());
    }

    @IsTest
    static void eachBucketCompilesToItsRuleAndNotAnyEarlierRule() {
        Map<String, String> predicates = dealSize(null, false).predicates(new CountingBinder());

        // Rules bind :p0-:p2, their negations :p3-:p5; a negation keeps rows whose field is empty, like `labelOf`.
        Assert.areEqual('(Amount >= :p0)', predicates.get('Large'));
        Assert.areEqual('(Amount >= :p1) AND ((Amount < :p3) OR (Amount = null))', predicates.get('Medium'));
        Assert.areEqual(
            '(LeadSource = :p2) AND ((Amount < :p3) OR (Amount = null)) AND ((Amount < :p4) OR (Amount = null))',
            predicates.get('Web')
        );
        Assert.areEqual(
            '((Amount < :p3) OR (Amount = null)) AND ((Amount < :p4) OR (Amount = null))' +
            ' AND ((LeadSource != :p5) OR (LeadSource = null))',
            predicates.get('Other')
        );
        Assert.isFalse(dealSize(null, true).predicates(new CountingBinder()).containsKey('Other'));
    }

    @IsTest
    static void negatedGroupsFollowDeMorganAndExcludeEmptyFieldsTheRuleMatched() {
        BoardBucketField bucketField = new BoardBucketField(
            'b',
            'B',
            new List<BoardBucketField.Rule>{
                new BoardBucketField.Rule(
                    'Not web',
                    BoardCondition.anyOf(
                        new List<BoardCondition.Node>{
                            BoardCondition.field('r', 'LeadSource', 'NEQ', new List<Object>{ 'Web' }),
                            BoardCondition.field('r', 'Name', 'LIKE', new List<Object>{ 'A%' })
                        }
                    )
                )
            },
            null,
            false
        );

        Assert.areEqual(
            '(((LeadSource = :p2) AND (LeadSource != null)) AND ((NOT (Name LIKE :p3)) OR (Name = null)))',
            bucketField.predicates(new CountingBinder()).get('Other')
        );
        Assert.areEqual('Not web', bucketField.labelOf(row(1, null)), 'An empty Lead source is not Web');
    }

    @IsTest
    static void rulesSharingALabelCompileToOneBucketPredicate() {
        BoardBucketField bucketField = new BoardBucketField(
            'b',
            'B',
            new List<BoardBucketField.Rule>{
                new BoardBucketField.Rule('Big', amountAtLeast(300)),
                new BoardBucketField.Rule('Web', leadSourceIs('Web')),
                new BoardBucketField.Rule('Big', leadSourceIs('Partner'))
            },
            'Big',
            false
        );

        Map<String, String> predicates = bucketField.predicates(new CountingBinder());

        Assert.areEqual(new List<String>{ 'Big', 'Web' }, bucketField.labels(), 'Fallback merges into the rule bucket');
        Assert.areEqual(
            '((Amount >= :p0)) OR ((LeadSource = :p2) AND ((Amount < :p3) OR (Amount = null))' +
                ' AND ((LeadSource != :p4) OR (LeadSource = null))) OR (((Amount < :p3) OR (Amount = null))' +
                ' AND ((LeadSource != :p4) OR (LeadSource = null)) AND ((LeadSource != :p5) OR (LeadSource = null)))',
            predicates.get('Big')
        );
    }

    @IsTest
    static void parsesTheBucketFieldConfigShape() {
        Map<String, Object> condition = new Map<String, Object>{
            'logic' => 'OR',
            'conditions' => new List<Object>{
                new Map<String, Object>{ 'id' => 'c1', 'fieldPath' => 'Amount', 'operator' => 'GTE', 'value' => 300 }
            }
        };
        BoardBucketField bucketField = BoardBucketField.fromConfig(
            new Map<String, Object>{
                'id' => 'dealSize',
                'label' => 'Deal size',
                'rules' => new List<Object>{
                    new Map<String, Object>{ 'label' => ' Large ', 'condition' => condition, 'colour' => '#ff0000' }
                }
            }
        );

        Assert.areEqual('dealSize', bucketField.id);
        Assert.areEqual('Deal size', bucketField.label);
        Assert.areEqual(1, bucketField.rules.size());
        Assert.areEqual('Large', bucketField.rules[0].label);
        Assert.areEqual('#ff0000', bucketField.rules[0].colour);
        Assert.areEqual(condition, bucketField.rules[0].rawCondition);
        Assert.areEqual('Other', bucketField.fallbackLabel, 'No fallback config: "Other"');
        Assert.isFalse(bucketField.excludeFallback);

        BoardBucketField excluding = BoardBucketField.fromConfig(
            new Map<String, Object>{
                'id' => 'x',
                'rules' => new List<Object>{ new Map<String, Object>{ 'label' => 'A', 'condition' => condition } },
                'fallback' => new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true }
            }
        );
        Assert.areEqual('Rest', excluding.fallbackLabel);
        Assert.isTrue(excluding.excludeFallback);
    }

    @IsTest
    static void rejectsInvalidBucketFieldConfigs() {
        Map<String, Object> condition = new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{ 'fieldPath' => 'Amount', 'operator' => 'GTE', 'value' => 1 }
            }
        };
        List<Object> twentySix = new List<Object>();
        for (Integer i = 0; i < 26; i++) {
            twentySix.add(new Map<String, Object>{ 'label' => 'R' + i, 'condition' => condition });
        }
        List<Object> twentyFive = new List<Object>(twentySix);
        twentyFive.remove(25);
        Assert.areEqual(
            25,
            BoardBucketField.fromConfig(new Map<String, Object>{ 'id' => 'b', 'rules' => twentyFive }).rules.size()
        );

        assertConfigError(new Map<String, Object>{ 'id' => 'b', 'rules' => twentySix }, 'at most 25');
        assertConfigError(new Map<String, Object>{ 'rules' => twentyFive }, 'id');
        assertConfigError(new Map<String, Object>{ 'id' => 'b', 'rules' => new List<Object>() }, 'at least one');
        assertConfigError(
            new Map<String, Object>{
                'id' => 'b',
                'rules' => new List<Object>{ new Map<String, Object>{ 'label' => ' ', 'condition' => condition } }
            },
            'label'
        );
        assertConfigError(
            new Map<String, Object>{
                'id' => 'b',
                'rules' => new List<Object>{
                    new Map<String, Object>{
                        'label' => 'A',
                        'condition' => new Map<String, Object>{ 'logic' => 'AND', 'conditions' => new List<Object>() }
                    }
                }
            },
            'no conditions'
        );
        assertConfigError('not a map', 'Bucket field');
    }

    @IsTest
    static void widgetsReferenceABucketFieldById() {
        Assert.areEqual('dealSize', BoardBucketField.referencedId('bucket:dealSize'));
        Assert.isNull(BoardBucketField.referencedId('Amount'));
        Assert.isNull(BoardBucketField.referencedId(null));

        List<Object> configs = new List<Object>{
            new Map<String, Object>{
                'id' => 'dealSize',
                'rules' => new List<Object>{
                    new Map<String, Object>{
                        'label' => 'A',
                        'condition' => new Map<String, Object>{
                            'fieldPath' => 'Amount',
                            'operator' => 'GTE',
                            'value' => 1
                        }
                    }
                }
            }
        };
        Assert.areEqual('dealSize', BoardBucketField.find(configs, 'dealSize').id);
        try {
            BoardBucketField.find(configs, 'missing');
            Assert.fail('Expected an unknown Bucket field error');
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, error.category);
            Assert.isTrue(error.getMessage().contains('missing'), error.getMessage());
        }
    }

    @IsTest
    static void formulaGroupingErrorPointsToBucketFields() {
        String message = BoardBucketField.formulaGroupingMessage('Is_Big_Deal__c');
        Assert.isTrue(message.contains('Is_Big_Deal__c'), message);
        Assert.isTrue(message.contains('Bucket field'), message);
    }

    private static void assertConfigError(Object raw, String expectedFragment) {
        try {
            BoardBucketField.fromConfig(raw);
            Assert.fail('Expected a config error for ' + JSON.serialize(raw));
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, error.category);
            Assert.isTrue(
                error.getMessage().containsIgnoreCase(expectedFragment),
                'Expected "' + expectedFragment + '" in: ' + error.getMessage()
            );
        }
    }
}