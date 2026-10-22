with Check;
with Ledger_Core.Reports;
with Ledger_Core.Wire;

procedure Test_Reports is
   use Ledger_Core;
   use Ledger_Core.Reports;
   use type Wire.Balance_Sheet_Report;
   use type Wire.Income_Report;
   use type Wire.Cash_Flow_Report;

   --  Signup deposit of 177600, then buy 1000 rounds @ 2500 (value 25000,
   --  costs 375): cash 152225, holdings 25000, costs 375.
   After_Buy : constant Wire.Account_Totals :=
     (1 => (Debits => 177_600, Credits => 25_375),
      2 => (Debits => 25_000, Credits => 0),
      3 => (Debits => 0, Credits => 177_600),
      4 => (Debits => 0, Credits => 0),
      5 => (Debits => 375, Credits => 0));

   Sheet  : Wire.Balance_Sheet_Report;
   Income : Wire.Income_Report;
   Flow   : Wire.Cash_Flow_Report;
   Result : Status;
   Totals : Wire.Account_Totals;
   Act    : Wire.Activity;
begin
   --  Valid_Totals, Total_Debits, Total_Credits
   Check.Holds ("valid totals", Valid_Totals (After_Buy));
   Totals := After_Buy;
   Totals (2).Credits := -1;
   Check.Holds ("negative total invalid", not Valid_Totals (Totals));
   Totals := After_Buy;
   Totals (5).Debits := Max_Aggregate + 1;
   Check.Holds ("over max invalid", not Valid_Totals (Totals));
   Check.Eq ("total debits", Total_Debits (After_Buy), 202_975);
   Check.Eq ("total credits", Total_Credits (After_Buy), 202_975);

   --  Balance_Sheet
   Balance_Sheet (After_Buy, Sheet, Result);
   Check.Is_Status ("sheet ok", Result, Ok);
   Check.Holds
     ("sheet values",
      Sheet = (Cash => 152_225, Holdings => 25_000, Total_Assets => 177_225,
               Owners_Capital => 177_600, Net_Income => -375,
               Total_Equity => 177_225, Total_Liabilities => 0));

   --  After a revalue up by 1000: gain 1000, holdings 26000.
   Totals := After_Buy;
   Totals (2).Debits := 26_000;
   Totals (4).Credits := 1_000;
   Balance_Sheet (Totals, Sheet, Result);
   Check.Is_Status ("sheet after gain", Result, Ok);
   Check.Eq ("assets after gain", Sheet.Total_Assets, 178_225);
   Check.Eq ("net income after gain", Sheet.Net_Income, 625);
   Check.Eq ("equity after gain", Sheet.Total_Equity, 178_225);

   --  Doctored: holdings debit one cent too high.
   Totals := After_Buy;
   Totals (2).Debits := 25_001;
   Balance_Sheet (Totals, Sheet, Result);
   Check.Is_Status ("doctored totals unbalanced", Result, Unbalanced);
   Check.Eq ("doctored sheet zeroed", Sheet.Total_Assets, 0);

   --  Balanced but cash negative.
   Totals := (others => (0, 0));
   Totals (1).Credits := 100;
   Totals (3).Debits := 100;
   Balance_Sheet (Totals, Sheet, Result);
   Check.Is_Status ("negative cash", Result, Negative_Balance);
   Totals := (others => (0, 0));
   Totals (2).Credits := 100;
   Totals (3).Debits := 100;
   Balance_Sheet (Totals, Sheet, Result);
   Check.Is_Status ("negative holdings", Result, Negative_Balance);
   Totals := (others => (0, 0));
   Balance_Sheet (Totals, Sheet, Result);
   Check.Is_Status ("empty ledger", Result, Ok);
   Totals (1).Debits := -5;
   Balance_Sheet (Totals, Sheet, Result);
   Check.Is_Status ("negative debit", Result, Out_Of_Range);
   Totals (1).Debits := Max_Aggregate + 1;
   Balance_Sheet (Totals, Sheet, Result);
   Check.Is_Status ("debit over max", Result, Out_Of_Range);

   --  Income_Statement: gain/loss account saw 1700 credits and 200
   --  debits (net 1500); costs 375; 1000 of the gain was realized.
   Totals := (others => (0, 0));
   Totals (4) := (Debits => 200, Credits => 1_700);
   Totals (5) := (Debits => 375, Credits => 0);
   Income_Statement (Totals, 1_000, Income, Result);
   Check.Is_Status ("income ok", Result, Ok);
   Check.Holds
     ("income values",
      Income = (Realized_Gain => 1_000, Unrealized_Gain => 500,
                Trading_Gain_Total => 1_500, Trading_Costs => 375,
                Net_Income => 1_125));
   Income_Statement (Totals, -2_000, Income, Result);
   Check.Is_Status ("negative realized ok", Result, Ok);
   Check.Eq ("unrealized when realized is a loss",
             Income.Unrealized_Gain, 3_500);
   Income_Statement (Totals, Max_Gain + 1, Income, Result);
   Check.Is_Status ("realized over max", Result, Out_Of_Range);
   Check.Eq ("income zeroed", Income.Net_Income, 0);
   Totals (5).Debits := -1;
   Income_Statement (Totals, 0, Income, Result);
   Check.Is_Status ("income bad totals", Result, Out_Of_Range);

   --  Valid_Activity
   Act := (others => (others => (0, 0)));
   Check.Holds ("empty activity valid", Valid_Activity (Act));
   Act (3, 5).Credits := -1;
   Check.Holds ("negative activity invalid", not Valid_Activity (Act));
   Act (3, 5).Credits := Max_Aggregate + 1;
   Check.Holds ("big activity invalid", not Valid_Activity (Act));

   --  Cash_Flow: deposit 177600; buy V 25000 + costs 375; sell V 10000
   --  with costs 375 (cash in 9625); revalue 1000 up.
   Act := (others => (others => (0, 0)));
   Act (0, 1).Debits := 177_600;
   Act (0, 3).Credits := 177_600;
   Act (1, 2).Debits := 25_000;
   Act (1, 5).Debits := 375;
   Act (1, 1).Credits := 25_375;
   Act (2, 1).Debits := 9_625;
   Act (2, 5).Debits := 375;
   Act (2, 2).Credits := 10_000;
   Act (3, 2).Debits := 1_000;
   Act (3, 4).Credits := 1_000;
   Cash_Flow (Act, 0, 161_850, Flow, Result);
   Check.Is_Status ("flow ok", Result, Ok);
   Check.Holds
     ("flow values",
      Flow = (Financing => 177_600, Investing => -15_000,
              Operating => -750, Net_Change => 161_850));
   Cash_Flow (Act, 100, 161_950, Flow, Result);
   Check.Is_Status ("flow with opening cash", Result, Ok);
   Cash_Flow (Act, 0, 161_851, Flow, Result);
   Check.Is_Status ("closing off by a cent", Result, Not_Reconciled);
   Check.Eq ("flow zeroed", Flow.Net_Change, 0);
   Cash_Flow (Act, 1, 161_850, Flow, Result);
   Check.Is_Status ("opening off by a cent", Result, Not_Reconciled);
   Act (3, 1).Debits := 5;  --  cash moved by a revalue: impossible
   Cash_Flow (Act, 0, 161_855, Flow, Result);
   Check.Is_Status ("stray cash movement", Result, Not_Reconciled);
   Act (3, 1).Debits := Max_Aggregate + 1;
   Cash_Flow (Act, 0, 0, Flow, Result);
   Check.Is_Status ("activity out of range", Result, Out_Of_Range);
   Act (3, 1).Debits := 0;
   Cash_Flow (Act, Max_Aggregate + 1, 0, Flow, Result);
   Check.Is_Status ("opening out of range", Result, Out_Of_Range);
   Cash_Flow (Act, 0, -Max_Aggregate - 1, Flow, Result);
   Check.Is_Status ("closing out of range", Result, Out_Of_Range);
   Act := (others => (others => (0, 0)));
   Cash_Flow (Act, 7, 7, Flow, Result);
   Check.Is_Status ("no activity", Result, Ok);

   --  Net (one cell of an activity grid)
   Act := (others => (others => (0, 0)));
   Act (2, 5) := (Debits => 375, Credits => 100);
   Check.Eq ("net of a cell", Net (Act, 2, 5), 275);
   Check.Eq ("net of an empty cell", Net (Act, 0, 1), 0);
   Act (1, 2) := (Debits => 10, Credits => 30);
   Check.Eq ("net can be negative", Net (Act, 1, 2), -20);

   --  Period (balance sheets, income statement and cash flow in one call)
   declare
      use type Wire.Totals;
      use type Wire.Period_Report;
      Zero  : constant Wire.Totals := (others => (others => (0, 0)));
      Opens : Wire.Totals := Zero;
      Close : Wire.Totals := Zero;
      Rep   : Wire.Period_Report;
   begin
      --  Opening: signup deposit. Closing: after buying 1000 rounds
      --  (value 25000, costs 375) and a revalue gain of 1000.
      Opens (0, 1).Debits := 177_600;
      Opens (0, 3).Credits := 177_600;
      Close := Opens;
      Close (1, 2).Debits := 25_000;
      Close (1, 5).Debits := 375;
      Close (1, 1).Credits := 25_375;
      Close (3, 2).Debits := 1_000;
      Close (3, 4).Credits := 1_000;
      Period (Opens, Close, 0, Rep, Result);
      Check.Is_Status ("period", Result, Ok);
      Check.Eq ("period opening cash", Rep.Opening.Cash, 177_600);
      Check.Eq ("period opening equity", Rep.Opening.Total_Equity, 177_600);
      Check.Eq ("period closing cash", Rep.Closing.Cash, 152_225);
      Check.Eq ("period closing holdings", Rep.Closing.Holdings, 26_000);
      Check.Eq ("period closing equity", Rep.Closing.Total_Equity, 178_225);
      Check.Eq ("period gain total", Rep.Income.Trading_Gain_Total, 1_000);
      Check.Eq ("period costs", Rep.Income.Trading_Costs, 375);
      Check.Eq ("period net income", Rep.Income.Net_Income, 625);
      Check.Eq ("period unrealized", Rep.Income.Unrealized_Gain, 1_000);
      Check.Eq ("period investing", Rep.Flow.Investing, -25_000);
      Check.Eq ("period operating", Rep.Flow.Operating, -375);
      Check.Eq ("period net change", Rep.Flow.Net_Change, -25_375);
      Check.Eq ("period change in net income to date",
                Rep.Closing.Net_Income - Rep.Opening.Net_Income, 625);
      Period (Opens, Close, 400, Rep, Result);
      Check.Eq ("period unrealized with realized", Rep.Income.Unrealized_Gain,
                600);
      Period (Close, Close, 0, Rep, Result);
      Check.Is_Status ("empty period", Result, Ok);
      Check.Eq ("empty period net income", Rep.Income.Net_Income, 0);
      Period (Close, Opens, 0, Rep, Result);
      Check.Is_Status ("period backwards", Result, Bad_Order);
      Check.Holds ("period error zeroed", Rep = Zero_Period);
      Period (Opens, Close, Max_Gain + 1, Rep, Result);
      Check.Is_Status ("period realized out of range", Result, Out_Of_Range);
      Opens (0, 1).Debits := Opens (0, 1).Debits + 1;
      Period (Opens, Close, 0, Rep, Result);
      Check.Is_Status ("period unbalanced opening", Result, Unbalanced);
      Opens := Zero;
      Opens (0, 1).Debits := 5_000_000_000_000_000_000;
      Period (Opens, Close, 0, Rep, Result);
      Check.Is_Status ("period invalid opening", Result, Out_Of_Range);
      Close := Zero;
      Close (0, 2).Credits := 5;
      Close (0, 3).Debits := 5;
      Period (Zero, Close, 0, Rep, Result);
      Check.Is_Status ("period negative closing holdings", Result,
                       Negative_Balance);
      Close := Zero;
      Close (0, 1).Debits := 100;
      Close (0, 3).Credits := 100;
      Close (3, 1).Debits := 7;
      Close (3, 4).Credits := 7;
      Period (Zero, Close, 0, Rep, Result);
      Check.Is_Status ("period cash outside the patterns", Result,
                       Not_Reconciled);
   end;
end Test_Reports;
