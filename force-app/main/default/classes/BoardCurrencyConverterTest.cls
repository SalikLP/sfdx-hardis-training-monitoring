/**
 * Engine-unit tests for `BoardCurrencyConverter`, fed with an in-memory rate table (corporate USD, EUR at 0.9,
 * JPY at 150, inactive DKK at 6.5). Expected values are worked by hand: `amount ÷ rate[from] × rate[to]`.
 */
@IsTest
private class BoardCurrencyConverterTest {
    private static BoardCurrencyConverter converter() {
        return BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('USD', 1, true),
                new BoardCurrencyConverter.Rate('EUR', 0.9, false),
                new BoardCurrencyConverter.Rate('JPY', 150, false),
                // Inactive currencies keep their rate; records may still carry them.
                new BoardCurrencyConverter.Rate('DKK', 6.5, false)
            }
        );
    }

    @IsTest
    static void corporateAmountsConvertToAnotherCurrency() {
        Assert.areEqual(90.0000000000, converter().convert(100, 'USD', 'EUR'));
        Assert.areEqual(15000.0000000000, converter().convert(100, 'USD', 'JPY'));
    }

    @IsTest
    static void recordAmountsConvertToCorporateCurrency() {
        BoardCurrencyConverter rates = converter();
        Assert.areEqual('USD', rates.getCorporateIsoCode());
        Assert.areEqual(100.0000000000, rates.toCorporate(90, 'EUR'));
        Assert.areEqual(20.0000000000, rates.toCorporate(3000, 'JPY'));
        Decimal corporateAmount = 250;
        Assert.areEqual(corporateAmount, rates.toCorporate(corporateAmount, 'USD'), 'Corporate amounts are unchanged');
    }

    @IsTest
    static void recordAmountsConvertBetweenTwoNonCorporateCurrenciesInOneStep() {
        // 3000 JPY ÷ 150 × 0.9 = 18 EUR
        Assert.areEqual(18.0000000000, converter().convert(3000, 'JPY', 'EUR'));
    }

    @IsTest
    static void conversionsKeepTenDecimalPlacesSoSumsDoNotDrift() {
        BoardCurrencyConverter rates = converter();
        // 100 EUR ÷ 0.9 = 111.111..., rounded half-even at 10 places, never to the currency's 2 places per row.
        Assert.areEqual(111.1111111111, rates.toCorporate(100, 'EUR'));
        Assert.areEqual(1.5384615385, rates.toCorporate(10, 'DKK'), '10 ÷ 6.5 = 1.538461538461...');
        Decimal sum = 0;
        for (Integer i = 0; i < 9; i++) {
            sum += rates.toCorporate(100, 'EUR');
        }
        Assert.areEqual(999.9999999999, sum, 'Nine rows of 100 EUR stay within 1E-9 of 1,000 USD');
    }

    @IsTest
    static void currencyCodesAreCaseInsensitive() {
        Assert.areEqual(100.0000000000, converter().toCorporate(90, 'eur'));
    }

    @IsTest
    static void inactiveCurrenciesStillConvert() {
        Assert.areEqual(10.0000000000, converter().toCorporate(65, 'DKK'));
    }

    @IsTest
    static void unknownOrMissingCurrencyCodesFailWithQueryError() {
        for (String isoCode : new List<String>{ 'XYZ', null, '' }) {
            try {
                converter().toCorporate(100, isoCode);
                Assert.fail('Expected an unknown currency error for ' + isoCode);
            } catch (BoardErrors.BoardException error) {
                Assert.areEqual(BoardErrors.QUERY_ERROR, error.category);
                Assert.isTrue(error.getMessage().contains('currency'), error.getMessage());
            }
        }
    }

    @IsTest
    static void nullAmountsStayNull() {
        Assert.isNull(converter().toCorporate(null, 'EUR'));
    }

    @IsTest
    static void singleCurrencyConverterIsANoOp() {
        BoardCurrencyConverter single = BoardCurrencyConverter.singleCurrency();
        Assert.isFalse(single.isMultiCurrency());
        Assert.areEqual(123.45, single.toCorporate(123.45, null));
        Assert.areEqual(123.45, single.convert(123.45, 'EUR', 'USD'));
        Assert.isNull(single.isoCodePath('Amount', Schema.DisplayType.CURRENCY), 'No CurrencyIsoCode to select');
    }

    @IsTest
    static void isoCodePathPointsAtTheRecordOwningACurrencyValue() {
        BoardCurrencyConverter rates = converter();
        Assert.isTrue(rates.isMultiCurrency());
        Assert.areEqual('CurrencyIsoCode', rates.isoCodePath('Amount', Schema.DisplayType.CURRENCY));
        Assert.areEqual(
            'Account.Parent.CurrencyIsoCode',
            rates.isoCodePath('Account.Parent.AnnualRevenue', Schema.DisplayType.CURRENCY)
        );
        Assert.isNull(rates.isoCodePath('Probability', Schema.DisplayType.PERCENT), 'Only currency values convert');
        Assert.isNull(rates.isoCodePath('NumberOfEmployees', Schema.DisplayType.INTEGER));
        Assert.isNull(rates.isoCodePath(null, null), 'COUNT has no value field');
    }

    @IsTest
    static void displayCurrencyIsTheRequestedCodeOrTheViewersCurrency() {
        BoardCurrencyConverter rates = converter();
        Assert.areEqual('EUR', rates.displayIsoCode(new Map<String, Object>{ 'displayCurrency' => ' eur ' }));
        Assert.areEqual('JPY', rates.displayIsoCode(new Map<String, Object>{ 'displayCurrency' => 'JPY' }));

        BoardCurrencyConverter withViewer = BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('USD', 1, true),
                new BoardCurrencyConverter.Rate(UserInfo.getDefaultCurrency(), 1, false)
            }
        );
        Assert.areEqual(UserInfo.getDefaultCurrency(), withViewer.displayIsoCode(new Map<String, Object>()));
        Assert.areEqual(
            UserInfo.getDefaultCurrency(),
            withViewer.displayIsoCode(new Map<String, Object>{ 'displayCurrency' => '' })
        );
    }

    @IsTest
    static void unknownDisplayCurrencyFailsWithQueryError() {
        try {
            converter().displayIsoCode(new Map<String, Object>{ 'displayCurrency' => 'XYZ' });
            Assert.fail('Expected an unknown currency error');
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.QUERY_ERROR, error.category);
        }
    }

    @IsTest
    static void onlySumAvgMinMaxOfCurrencyFieldsCarryTheDisplayCurrency() {
        BoardCurrencyConverter rates = converter();
        Map<String, Object> request = new Map<String, Object>{ 'displayCurrency' => 'EUR' };
        for (String aggregateFunction : new List<String>{ 'SUM', 'AVG', 'MIN', 'max' }) {
            Assert.areEqual('EUR', rates.isoCodeFor(aggregateFunction, 'CURRENCY', request), aggregateFunction);
        }
        Assert.isNull(rates.isoCodeFor('COUNT', null, request), 'Counts never convert');
        Assert.isNull(rates.isoCodeFor('COUNT_DISTINCT', 'CURRENCY', request), 'Distinct counts never convert');
        Assert.isNull(rates.isoCodeFor('AVG', 'PERCENT', request), 'Percentages never convert');
        Assert.isNull(rates.isoCodeFor('SUM', 'DOUBLE', request), 'Plain numbers never convert');
        Assert.isNull(rates.isoCodeFor('MAX', 'DATE', request));
    }

    @IsTest
    static void corporateAggregatesConvertToTheDisplayCurrency() {
        BoardCurrencyConverter rates = converter();
        Assert.areEqual(90.0000000000, rates.fromCorporate(100, 'EUR'));
        Assert.areEqual(15000.0000000000, rates.fromCorporate(100.0, 'JPY'));
        Decimal amount = 100;
        Assert.areEqual(amount, rates.fromCorporate(amount, 'USD'), 'Corporate display: unchanged');
        Assert.areEqual(7, rates.fromCorporate(7, null), 'No ISO code: not a currency amount, unchanged');
        Assert.isNull(rates.fromCorporate(null, 'EUR'));
    }

    @IsTest
    static void cursorChunkSumsMinsAndMaxesConvertButCountsDoNot() {
        BoardChartEngine.Partial bucket = new BoardChartEngine.Partial();
        bucket.sum = 300;
        bucket.count = 2;
        bucket.min = 100;
        bucket.max = 200;
        BoardQueryService.AggregateChunk chunk = new BoardQueryService.AggregateChunk();
        chunk.buckets = new List<BoardChartEngine.Partial>{ bucket };

        converter().toDisplay(chunk, 'EUR');

        Assert.areEqual(270.0000000000, bucket.sum);
        Assert.areEqual(2, bucket.count);
        Assert.areEqual(90.0000000000, bucket.min);
        Assert.areEqual(180.0000000000, bucket.max);

        converter().toDisplay(chunk, null);
        Assert.areEqual(270.0000000000, bucket.sum, 'No ISO code: nothing converts');
        Assert.isNull(converter().toDisplay((BoardQueryService.AggregateChunk) null, 'EUR'));
    }

    @IsTest
    static void chartPointsOfCurrencyMeasuresConvertAndCarryTheirIsoCode() {
        BoardChartQuery.ChartResult result = new BoardChartQuery.ChartResult();
        result.aggregateFunctions = new List<String>{ 'SUM', 'COUNT', 'AVG' };
        result.valueTypes = new List<String>{ 'CURRENCY', null, 'PERCENT' };
        result.points = new List<BoardChartEngine.ChartPoint>{ point(0, 1000), point(1, 4), point(2, 25) };

        converter().toDisplay(result, new Map<String, Object>{ 'displayCurrency' => 'JPY' });

        Assert.areEqual(new List<String>{ 'JPY', null, null }, result.currencyIsoCodes);
        Assert.areEqual(150000.0000000000, result.points[0].value);
        Assert.areEqual(4, result.points[1].value);
        Assert.areEqual(25, result.points[2].value);
    }

    @IsTest
    static void singleCurrencyOrgsFormatInTheOrgCurrencyWithoutConverting() {
        BoardCurrencyConverter single = BoardCurrencyConverter.singleCurrency();
        Map<String, Object> request = new Map<String, Object>{ 'displayCurrency' => 'EUR' };
        Assert.areEqual(UserInfo.getDefaultCurrency(), single.displayIsoCode(request), 'Org currency');
        Assert.areEqual(UserInfo.getDefaultCurrency(), single.isoCodeFor('SUM', 'CURRENCY', request));
        Assert.isNull(single.isoCodeFor('COUNT', null, request));
        Assert.areEqual(123.45, single.fromCorporate(123.45, UserInfo.getDefaultCurrency()));
    }

    private static BoardChartEngine.ChartPoint point(Integer measureIndex, Decimal value) {
        BoardChartEngine.ChartPoint point = new BoardChartEngine.ChartPoint();
        point.measureIndex = measureIndex;
        point.categoryKey = 'a';
        point.seriesKey = '__value__';
        point.value = value;
        return point;
    }

    @IsTest
    static void forRequestMatchesTheOrgAndIsReadOnce() {
        BoardCurrencyConverter first = BoardCurrencyConverter.forRequest();
        Assert.areEqual(UserInfo.isMultiCurrencyOrganization(), first.isMultiCurrency());
        Integer queries = Limits.getQueries();
        Assert.isTrue(first === BoardCurrencyConverter.forRequest(), 'Rates are cached for the request');
        Assert.areEqual(queries, Limits.getQueries());
        if (first.isMultiCurrency()) {
            String corporate = first.getCorporateIsoCode();
            Assert.isNotNull(corporate);
            Decimal amount = 42;
            Assert.areEqual(amount, first.toCorporate(amount, corporate));
        }
    }

    @IsTest
    static void configCurrencyIsTheRequestedCodeOrTheCorporateCurrency() {
        BoardCurrencyConverter rates = converter();
        Assert.areEqual('USD', rates.configIsoCode(new Map<String, Object>()), 'Default: corporate');
        Assert.areEqual('USD', rates.configIsoCode(new Map<String, Object>{ 'configCurrency' => null }));
        Assert.areEqual('USD', rates.configIsoCode(new Map<String, Object>{ 'configCurrency' => ' ' }));
        Assert.areEqual('EUR', rates.configIsoCode(new Map<String, Object>{ 'configCurrency' => ' eur ' }));
        Assert.isNull(
            BoardCurrencyConverter.singleCurrency().configIsoCode(new Map<String, Object>{ 'configCurrency' => 'EUR' }),
            'Single-currency orgs: no Config currency'
        );
        try {
            rates.configIsoCode(new Map<String, Object>{ 'configCurrency' => 'XYZ' });
            Assert.fail('Expected an unknown currency error');
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.QUERY_ERROR, error.category);
        }
    }

    @IsTest
    static void configAmountsConvertToTheDisplayCurrencyOnlyForCurrencyValues() {
        Map<String, Object> request = new Map<String, Object>{
            'configCurrency' => 'EUR',
            'thresholdAmounts' => new List<Object>{ 900, null, '1800', 'abc' }
        };

        // 900 EUR ÷ 0.9 × 150 = 150,000 JPY; 1,800 EUR = 300,000 JPY.
        List<Decimal> converted = converter().configToDisplay(request, 'thresholdAmounts', 'JPY');
        Assert.areEqual(4, converted.size());
        Assert.areEqual(150000.0000000000, converted[0]);
        Assert.isNull(converted[1]);
        Assert.areEqual(300000.0000000000, converted[2]);
        Assert.isNull(converted[3], 'Not a number');

        List<Decimal> asEntered = converter().configToDisplay(request, 'thresholdAmounts', null);
        Assert.areEqual(900, asEntered[0].intValue(), 'Not a currency value: as entered');
        Assert.areEqual(1800, asEntered[2].intValue());

        List<Decimal> corporate = converter()
            .configToDisplay(
                new Map<String, Object>{ 'thresholdAmounts' => new List<Object>{ 900 } },
                'thresholdAmounts',
                'EUR'
            );
        Assert.areEqual(810.0000000000, corporate[0], 'Default Config currency: corporate (900 USD = 810 EUR)');

        List<Decimal> single = BoardCurrencyConverter.singleCurrency()
            .configToDisplay(request, 'thresholdAmounts', 'USD');
        Assert.areEqual(900, single[0].intValue(), 'Single-currency orgs: as entered');

        Assert.isNull(converter().configToDisplay(new Map<String, Object>(), 'thresholdAmounts', 'JPY'));
    }

    @IsTest
    static void configCurrencyAmountsCompareInMemoryAsCorporateAmounts() {
        // 90 EUR = 100 USD (corporate): rows hold corporate amounts, as SOQL compares the ISO literal.
        Object eur = converter().configAmountBound(90, new Map<String, Object>{ 'configCurrency' => 'EUR' });
        Assert.areEqual(100.0000000000, ((BoardCurrencyConverter.IsoAmount) eur).corporateAmount);
        BoardCondition.Node over = BoardCondition.field('big', 'Amount', 'GT', new List<Object>{ eur });
        Assert.isTrue(over.evaluate(new Map<String, Object>{ 'Amount' => 100.01 }), '100.01 USD > 90 EUR');
        Assert.isFalse(over.evaluate(new Map<String, Object>{ 'Amount' => 100 }), '100 USD = 90 EUR');
        Assert.isFalse(over.evaluate(new Map<String, Object>{ 'Amount' => 95 }), '95 USD < 90 EUR');
        Assert.isFalse(over.evaluate(new Map<String, Object>{ 'Amount' => null }));

        BoardCondition.Node atMost = BoardCondition.field('big', 'Amount', 'LTE', new List<Object>{ eur });
        Assert.isTrue(atMost.evaluate(new Map<String, Object>{ 'Amount' => 100 }));
        BoardCondition.Node listed = BoardCondition.field('big', 'Amount', 'IN', new List<Object>{ eur });
        Assert.isTrue(listed.evaluate(new Map<String, Object>{ 'Amount' => 100 }), 'IN compares corporate too');

        Object corporate = converter().configAmountBound(250, new Map<String, Object>());
        BoardCondition.Node plain = BoardCondition.field('big', 'Amount', 'GTE', new List<Object>{ corporate });
        Assert.isTrue(plain.evaluate(new Map<String, Object>{ 'Amount' => 250 }), 'Corporate Config currency');
    }

    @IsTest
    static void baseFilterAmountsBecomeIsoLiteralsInTheConfigCurrency() {
        Object eur = converter().configAmountBound(5000, new Map<String, Object>{ 'configCurrency' => ' eur ' });
        Assert.areEqual('EUR5000', ((BoardCurrencyConverter.IsoAmount) eur).toSoql());
        Object corporate = converter().configAmountBound(1234.50, new Map<String, Object>());
        Assert.areEqual('USD1234.50', ((BoardCurrencyConverter.IsoAmount) corporate).toSoql(), 'Default: corporate');
        Assert.isNull(converter().configAmountBound(null, new Map<String, Object>{ 'configCurrency' => 'EUR' }));

        Object plain = BoardCurrencyConverter.singleCurrency()
            .configAmountBound(5000, new Map<String, Object>{ 'configCurrency' => 'EUR' });
        Assert.isInstanceOfType(plain, Decimal.class, 'Single-currency orgs: a plain amount');

        BoardCurrencyConverter withInactive = BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('USD', 1, true),
                new BoardCurrencyConverter.Rate('DKK', 6.5, false, false)
            }
        );
        try {
            withInactive.configAmountBound(5000, new Map<String, Object>{ 'configCurrency' => 'DKK' });
            Assert.fail('Expected an inactive currency error');
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.QUERY_ERROR, error.category);
        }
    }

    @IsTest
    static void currencyOptionsListTheActiveCurrenciesOfAMultiCurrencyOrg() {
        BoardCurrencyConverter.CurrencyOptions options = BoardCurrencyConverter.getCurrencyOptions();
        Assert.areEqual(UserInfo.isMultiCurrencyOrganization(), options.multiCurrency);
        if (options.multiCurrency) {
            Assert.isTrue(options.isoCodes.contains(options.corporateIsoCode), String.valueOf(options.isoCodes));
        } else {
            Assert.isTrue(options.isoCodes.isEmpty());
        }

        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.singleCurrency();
        BoardCurrencyConverter.CurrencyOptions single = BoardCurrencyConverter.getCurrencyOptions();
        Assert.isFalse(single.multiCurrency, 'Single-currency orgs hide the Config currency setting');
        Assert.isTrue(single.isoCodes.isEmpty());
    }
}