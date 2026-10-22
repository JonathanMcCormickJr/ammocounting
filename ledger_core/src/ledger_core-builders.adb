package body Ledger_Core.Builders with SPARK_Mode is

   Blank : constant Wire.Posting := (0, 0, 0);

   procedure Build_Deposit
     (Cents  : Int64;
      Set    : out Wire.Posting_Set;
      Result : out Status)
   is
   begin
      Set := Empty_Set;
      if Cents < 1 then
         Result := Bad_Argument;
      elsif Cents > Max_Amount then
         Result := Out_Of_Range;
      else
         Set :=
           (Count    => 2,
            Reserved => 0,
            Items    =>
              (1      => (Cash_Account, Debit, Cents),
               2      => (Capital_Account, Credit, Cents),
               others => Blank));
         Result := Ok;
      end if;
   end Build_Deposit;

   procedure Build_Buy
     (Quote  : Wire.Buy_Quote;
      Set    : out Wire.Posting_Set;
      Result : out Status)
   is
   begin
      Set := Empty_Set;
      if Quote.Value not in 0 .. Max_Amount
        or else Quote.Spread not in 0 .. Max_Amount
        or else Quote.Fee not in 0 .. Max_Amount
        or else Quote.Costs not in 0 .. Max_Amount
        or else Quote.Total_Cash_Out not in 0 .. Max_Amount
      then
         Result := Out_Of_Range;
      elsif Quote.Costs /= Quote.Spread + Quote.Fee
        or else Quote.Total_Cash_Out /= Quote.Value + Quote.Costs
      then
         Result := Unbalanced;
      elsif Quote.Total_Cash_Out = 0 then
         Result := Bad_Argument;
      else
         declare
            Holding : constant Wire.Posting :=
              (Holdings_Account, Debit, Quote.Value);
            Cost    : constant Wire.Posting :=
              (Costs_Account, Debit, Quote.Costs);
            Cash    : constant Wire.Posting :=
              (Cash_Account, Credit, Quote.Total_Cash_Out);
         begin
            if Quote.Value > 0 and then Quote.Costs > 0 then
               Set := (3, 0, (1 => Holding, 2 => Cost, 3 => Cash,
                              others => Blank));
            elsif Quote.Value > 0 then
               Set := (2, 0, (1 => Holding, 2 => Cash, others => Blank));
            else
               Set := (2, 0, (1 => Cost, 2 => Cash, others => Blank));
            end if;
            Result := Ok;
         end;
      end if;
   end Build_Buy;

   procedure Build_Sell
     (Quote  : Wire.Sell_Quote;
      Set    : out Wire.Posting_Set;
      Result : out Status)
   is
   begin
      Set := Empty_Set;
      if Quote.Value not in 0 .. Max_Amount
        or else Quote.Spread not in 0 .. Max_Amount
        or else Quote.Fee not in 0 .. Max_Amount
        or else Quote.Costs not in 0 .. Max_Amount
        or else Quote.Net_Cash_In not in 0 .. Max_Amount
      then
         Result := Out_Of_Range;
      elsif Quote.Costs /= Quote.Spread + Quote.Fee
        or else Quote.Net_Cash_In + Quote.Costs /= Quote.Value
      then
         Result := Unbalanced;
      elsif Quote.Value = 0 then
         Result := Bad_Argument;
      else
         declare
            Proceeds : constant Wire.Posting :=
              (Cash_Account, Debit, Quote.Net_Cash_In);
            Cost     : constant Wire.Posting :=
              (Costs_Account, Debit, Quote.Costs);
            Holding  : constant Wire.Posting :=
              (Holdings_Account, Credit, Quote.Value);
         begin
            if Quote.Net_Cash_In > 0 and then Quote.Costs > 0 then
               Set := (3, 0, (1 => Proceeds, 2 => Cost, 3 => Holding,
                              others => Blank));
            elsif Quote.Net_Cash_In > 0 then
               Set := (2, 0, (1 => Proceeds, 2 => Holding,
                              others => Blank));
            else
               Set := (2, 0, (1 => Cost, 2 => Holding, others => Blank));
            end if;
            Result := Ok;
         end;
      end if;
   end Build_Sell;

   procedure Revalue
     (Market_Values : Wire.Int64_Array;
      Carrying      : Int64;
      Info          : out Wire.Revaluation;
      Set           : out Wire.Posting_Set;
      Result        : out Status)
   is
      Market : Int64 := 0;
   begin
      Info := No_Revaluation;
      Set  := Empty_Set;

      if Carrying not in 0 .. Max_Aggregate then
         Result := Out_Of_Range;
         return;
      end if;

      for I in Market_Values'Range loop
         pragma Loop_Invariant (Market in 0 .. Max_Aggregate);
         pragma Loop_Invariant
           (Big (Market) =
              Ledger_Core.Holdings.Sum_To
                (Market_Values, I - Market_Values'First));
         pragma Loop_Invariant
           (for all J in Market_Values'First .. I - 1 =>
              Market_Values (J) in 0 .. Max_Amount);
         if Market_Values (I) not in 0 .. Max_Amount
           or else Market + Market_Values (I) > Max_Aggregate
         then
            Result := Out_Of_Range;
            return;
         end if;
         Market := Market + Market_Values (I);
      end loop;

      if Market = Carrying then
         Info   := (Market, 0, 0, 0);
         Result := Ok;
      elsif Market > Carrying then
         if Market - Carrying > Max_Amount then
            Result := Out_Of_Range;
         else
            Info   := (Market, Market - Carrying, Gained, 0);
            Set    :=
              (Count    => 2,
               Reserved => 0,
               Items    =>
                 (1      => (Holdings_Account, Debit, Market - Carrying),
                  2      => (Gain_Account, Credit, Market - Carrying),
                  others => Blank));
            Result := Ok;
         end if;
      elsif Carrying - Market > Max_Amount then
         Result := Out_Of_Range;
      else
         Info   := (Market, Carrying - Market, Lost, 0);
         Set    :=
           (Count    => 2,
            Reserved => 0,
            Items    =>
              (1      => (Gain_Account, Debit, Carrying - Market),
               2      => (Holdings_Account, Credit, Carrying - Market),
               others => Blank));
         Result := Ok;
      end if;
   end Revalue;

end Ledger_Core.Builders;
