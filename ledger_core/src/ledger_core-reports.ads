with Ledger_Core.Wire;

--  The three financial statements, computed from account totals that Rails
--  aggregated with SQL SUM over validated postings. Accounts: 1 Cash,
--  2 Holdings, 3 Owner's Capital, 4 Trading Gain/Loss, 5 Trading Costs.
--  On any non-Ok status the report is all zeros.
package Ledger_Core.Reports with SPARK_Mode is

   use type Wire.Balance_Sheet_Report;
   use type Wire.Income_Report;
   use type Wire.Cash_Flow_Report;
   use type Wire.Period_Report;

   subtype Aggregate is Int64 range 0 .. Max_Aggregate;
   subtype Signed_Aggregate is Int64 range -Max_Aggregate .. Max_Aggregate;
   subtype Gain is Int64 range -Max_Gain .. Max_Gain;

   Cash     : constant := 1;
   Holdings : constant := 2;
   Capital  : constant := 3;
   Income   : constant := 4;
   Expense  : constant := 5;

   function Valid_Totals (T : Wire.Account_Totals) return Boolean is
     (for all A of T => A.Debits in Aggregate and then A.Credits in Aggregate);

   function Total_Debits (T : Wire.Account_Totals) return Big is
     (Big (T (1).Debits) + Big (T (2).Debits) + Big (T (3).Debits)
      + Big (T (4).Debits) + Big (T (5).Debits));

   function Total_Credits (T : Wire.Account_Totals) return Big is
     (Big (T (1).Credits) + Big (T (2).Credits) + Big (T (3).Credits)
      + Big (T (4).Credits) + Big (T (5).Credits));

   --  Ok iff every total is in 0 .. Max_Aggregate (else Out_Of_Range),
   --  total debits equal total credits (else Unbalanced), and cash and
   --  holdings are not negative (else Negative_Balance). When Ok,
   --  assets = liabilities + equity, with liabilities always zero.
   procedure Balance_Sheet
     (Totals : Wire.Account_Totals;
      Report : out Wire.Balance_Sheet_Report;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Valid_Totals (Totals)
          and then Total_Debits (Totals) = Total_Credits (Totals)
          and then Report.Cash >= 0
          and then Report.Holdings >= 0
          and then Report.Cash = Totals (Cash).Debits - Totals (Cash).Credits
          and then Report.Holdings =
                     Totals (Holdings).Debits - Totals (Holdings).Credits
          and then Report.Owners_Capital =
                     Totals (Capital).Credits - Totals (Capital).Debits
          and then Report.Net_Income =
                     (Totals (Income).Credits - Totals (Income).Debits)
                     - (Totals (Expense).Debits - Totals (Expense).Credits)
          and then Report.Total_Liabilities = 0
          and then Report.Total_Assets = Report.Cash + Report.Holdings
          and then Report.Total_Equity =
                     Report.Owners_Capital + Report.Net_Income
          and then Report.Total_Assets =
                     Report.Total_Liabilities + Report.Total_Equity
        else Report = (others => 0));

   --  Totals are the period's activity. Realized_Gain comes from
   --  Cost_Basis.Compute. When Ok,
   --  net income = trading gain/loss total - trading costs.
   procedure Income_Statement
     (Totals        : Wire.Account_Totals;
      Realized_Gain : Int64;
      Report        : out Wire.Income_Report;
      Result        : out Status)
   with
     Post =>
       (if Result = Ok then
          Valid_Totals (Totals)
          and then Report.Realized_Gain = Realized_Gain
          and then Report.Trading_Gain_Total =
                     Totals (Income).Credits - Totals (Income).Debits
          and then Report.Trading_Costs =
                     Totals (Expense).Debits - Totals (Expense).Credits
          and then Report.Trading_Gain_Total =
                     Report.Realized_Gain + Report.Unrealized_Gain
          and then Report.Net_Income =
                     Report.Trading_Gain_Total - Report.Trading_Costs
        else Report = (others => 0));

   function Valid_Activity (A : Wire.Activity) return Boolean is
     (for all K in 0 .. 3 =>
        (for all Acct in 1 .. 5 =>
           A (K, Acct).Debits in Aggregate
           and then A (K, Acct).Credits in Aggregate));

   --  Debits minus credits of one (kind, account) cell.
   function Net (Activity : Wire.Activity; K, Acct : Integer) return Int64
   is (Activity (K, Acct).Debits - Activity (K, Acct).Credits)
   with
     Pre  => Valid_Activity (Activity) and then K in 0 .. 3
             and then Acct in 1 .. 5,
     Post => Net'Result in Signed_Aggregate;

   --  Activity is indexed (kind 0 .. 3, account 1 .. 5). Financing is the
   --  cash from deposits; investing is cash in from sells minus cash out
   --  for buys, at holdings value; operating is minus the trading costs
   --  paid. Not_Reconciled unless the classified flows equal the actual
   --  cash movement and Opening_Cash + Net_Change = Closing_Cash.
   procedure Cash_Flow
     (Activity     : Wire.Activity;
      Opening_Cash : Int64;
      Closing_Cash : Int64;
      Report       : out Wire.Cash_Flow_Report;
      Result       : out Status)
   with
     Post =>
       (if Result = Ok then
          Valid_Activity (Activity)
          and then Report.Financing = Net (Activity, 0, Cash)
          and then Report.Investing =
                     -Net (Activity, 1, Holdings) - Net (Activity, 2, Holdings)
          and then Report.Operating =
                     -Net (Activity, 1, Expense) - Net (Activity, 2, Expense)
          and then Report.Net_Change =
            Report.Financing + Report.Investing + Report.Operating
          and then Opening_Cash + Report.Net_Change = Closing_Cash
        else Report = (others => 0));

   Zero_Period : constant Wire.Period_Report :=
     (Opening => (others => 0),
      Closing => (others => 0),
      Income  => (others => 0),
      Flow    => (others => 0));

   --  The whole period report from the running totals at its two ends:
   --  Closing - Opening is the period's activity (Out_Of_Range for invalid
   --  totals, Unbalanced, Bad_Order when Closing is below Opening in any
   --  cell), the balance sheets come from the totals themselves, and the
   --  income statement and cash flow from the activity. When Ok, net income
   --  equals the change in net income to date, and opening cash plus the net
   --  change equals closing cash.
   procedure Period
     (Opening       : Wire.Totals;
      Closing       : Wire.Totals;
      Realized_Gain : Int64;
      Report        : out Wire.Period_Report;
      Result        : out Status)
   with
     Post =>
       (if Result = Ok then
          Report.Income.Net_Income =
            Report.Closing.Net_Income - Report.Opening.Net_Income
          and then Report.Income.Realized_Gain = Realized_Gain
          and then Report.Opening.Cash + Report.Flow.Net_Change =
                     Report.Closing.Cash
          and then Report.Opening.Total_Assets =
                     Report.Opening.Total_Liabilities
                     + Report.Opening.Total_Equity
          and then Report.Closing.Total_Assets =
                     Report.Closing.Total_Liabilities
                     + Report.Closing.Total_Equity
        else Report = Zero_Period);

end Ledger_Core.Reports;
