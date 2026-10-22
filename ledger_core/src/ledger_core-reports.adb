with Ledger_Core.Running;

package body Ledger_Core.Reports with SPARK_Mode is

   procedure Balance_Sheet
     (Totals : Wire.Account_Totals;
      Report : out Wire.Balance_Sheet_Report;
      Result : out Status)
   is
   begin
      Report := (others => 0);
      if not Valid_Totals (Totals) then
         Result := Out_Of_Range;
      elsif Total_Debits (Totals) /= Total_Credits (Totals) then
         Result := Unbalanced;
      elsif Totals (Cash).Debits < Totals (Cash).Credits
        or else Totals (Holdings).Debits < Totals (Holdings).Credits
      then
         Result := Negative_Balance;
      else
         declare
            Cash_Balance     : constant Int64 :=
              Totals (Cash).Debits - Totals (Cash).Credits;
            Holdings_Balance : constant Int64 :=
              Totals (Holdings).Debits - Totals (Holdings).Credits;
            Capital_Balance  : constant Int64 :=
              Totals (Capital).Credits - Totals (Capital).Debits;
            Net_Income       : constant Int64 :=
              (Totals (Income).Credits - Totals (Income).Debits)
              - (Totals (Expense).Debits - Totals (Expense).Credits);
         begin
            Report :=
              (Cash              => Cash_Balance,
               Holdings          => Holdings_Balance,
               Total_Assets      => Cash_Balance + Holdings_Balance,
               Owners_Capital    => Capital_Balance,
               Net_Income        => Net_Income,
               Total_Equity      => Capital_Balance + Net_Income,
               Total_Liabilities => 0);
            Result := Ok;
         end;
      end if;
   end Balance_Sheet;

   procedure Income_Statement
     (Totals        : Wire.Account_Totals;
      Realized_Gain : Int64;
      Report        : out Wire.Income_Report;
      Result        : out Status)
   is
   begin
      Report := (others => 0);
      if not Valid_Totals (Totals) or else Realized_Gain not in Gain then
         Result := Out_Of_Range;
      else
         declare
            Gain_Total : constant Int64 :=
              Totals (Income).Credits - Totals (Income).Debits;
            Costs      : constant Int64 :=
              Totals (Expense).Debits - Totals (Expense).Credits;
         begin
            Report :=
              (Realized_Gain      => Realized_Gain,
               Unrealized_Gain    => Gain_Total - Realized_Gain,
               Trading_Gain_Total => Gain_Total,
               Trading_Costs      => Costs,
               Net_Income         => Gain_Total - Costs);
            Result := Ok;
         end;
      end if;
   end Income_Statement;

   procedure Cash_Flow
     (Activity     : Wire.Activity;
      Opening_Cash : Int64;
      Closing_Cash : Int64;
      Report       : out Wire.Cash_Flow_Report;
      Result       : out Status)
   is
   begin
      Report := (others => 0);
      if not Valid_Activity (Activity)
        or else Opening_Cash not in Signed_Aggregate
        or else Closing_Cash not in Signed_Aggregate
      then
         Result := Out_Of_Range;
         return;
      end if;

      declare
         Financing  : constant Int64 := Net (Activity, 0, Cash);
         Investing  : constant Int64 :=
           -Net (Activity, 1, Holdings) - Net (Activity, 2, Holdings);
         Operating  : constant Int64 :=
           -Net (Activity, 1, Expense) - Net (Activity, 2, Expense);
         Net_Change : constant Int64 := Financing + Investing + Operating;
         Actual     : constant Int64 :=
           Net (Activity, 0, Cash) + Net (Activity, 1, Cash)
           + Net (Activity, 2, Cash) + Net (Activity, 3, Cash);
      begin
         if Net_Change /= Actual
           or else Opening_Cash + Net_Change /= Closing_Cash
         then
            Result := Not_Reconciled;
         else
            Report :=
              (Financing  => Financing,
               Investing  => Investing,
               Operating  => Operating,
               Net_Change => Net_Change);
            Result := Ok;
         end if;
      end;
   end Cash_Flow;

   procedure Period
     (Opening       : Wire.Totals;
      Closing       : Wire.Totals;
      Realized_Gain : Int64;
      Report        : out Wire.Period_Report;
      Result        : out Status)
   is
      Activity            : Wire.Totals;
      Open_Sums           : Wire.Account_Totals;
      Close_Sums          : Wire.Account_Totals;
      Activity_Sums       : Wire.Account_Totals;
      Opening_Sheet       : Wire.Balance_Sheet_Report;
      Closing_Sheet       : Wire.Balance_Sheet_Report;
      Statement           : Wire.Income_Report;
      Flow                : Wire.Cash_Flow_Report;
   begin
      Report := Zero_Period;
      Running.Diff_Totals (Closing, Opening, Activity, Result);
      if Result /= Ok then
         return;
      end if;
      Running.Collapse_Kinds (Opening, Open_Sums, Result);
      if Result /= Ok then
         return;
      end if;
      Running.Collapse_Kinds (Closing, Close_Sums, Result);
      if Result /= Ok then
         return;
      end if;
      Running.Collapse_Kinds (Activity, Activity_Sums, Result);
      if Result /= Ok then
         return;
      end if;
      Balance_Sheet (Open_Sums, Opening_Sheet, Result);
      if Result /= Ok then
         return;
      end if;
      Balance_Sheet (Close_Sums, Closing_Sheet, Result);
      if Result /= Ok then
         return;
      end if;
      Income_Statement (Activity_Sums, Realized_Gain, Statement, Result);
      if Result /= Ok then
         return;
      end if;
      Cash_Flow
        (Activity, Opening_Sheet.Cash, Closing_Sheet.Cash, Flow, Result);
      if Result /= Ok then
         return;
      end if;
      Report :=
        (Opening => Opening_Sheet,
         Closing => Closing_Sheet,
         Income  => Statement,
         Flow    => Flow);
      Result := Ok;
   end Period;

end Ledger_Core.Reports;
