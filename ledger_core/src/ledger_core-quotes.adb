package body Ledger_Core.Quotes with SPARK_Mode is

   procedure Market_Value
     (Qty        : Int64;
      Unit_Price : Int64;
      Value      : out Int64;
      Result     : out Status)
   is
   begin
      Value := 0;
      if Qty not in Quantity or else Unit_Price not in Price then
         Result := Out_Of_Range;
      elsif Value_Of (Qty, Unit_Price) > Max_Amount then
         Result := Out_Of_Range;
      else
         Value  := Int64 (Value_Of (Qty, Unit_Price));
         Result := Ok;
      end if;
   end Market_Value;

   procedure Quote_Buy
     (Qty            : Int64;
      Unit_Price     : Int64;
      Spread_Bps     : Int64;
      Fee_Bps        : Int64;
      Cash_Available : Int64;
      Quote          : out Wire.Buy_Quote;
      Result         : out Status)
   is
      Value : Int64;
   begin
      Quote := (others => 0);
      Market_Value (Qty, Unit_Price, Value, Result);
      if Result /= Ok then
         return;
      elsif Spread_Bps not in Rate or else Fee_Bps not in Rate then
         Result := Out_Of_Range;
         return;
      end if;

      declare
         Spread : constant Int64 := Int64 (Spread_Of (Value, Spread_Bps));
         Fee    : constant Int64 := Int64 (Fee_Of (Value, Fee_Bps));
         Total  : constant Int64 := Value + Spread + Fee;
      begin
         if Total > Max_Amount then
            Result := Out_Of_Range;
         elsif Total > Cash_Available then
            Result := Insufficient_Cash;
         else
            Quote  := (Value          => Value,
                       Spread         => Spread,
                       Fee            => Fee,
                       Costs          => Spread + Fee,
                       Total_Cash_Out => Total);
            Result := Ok;
         end if;
      end;
   end Quote_Buy;

   procedure Quote_Sell
     (Qty        : Int64;
      Qty_Held   : Int64;
      Unit_Price : Int64;
      Spread_Bps : Int64;
      Fee_Bps    : Int64;
      Quote      : out Wire.Sell_Quote;
      Result     : out Status)
   is
      Value : Int64;
   begin
      Quote := (others => 0);
      Market_Value (Qty, Unit_Price, Value, Result);
      if Result /= Ok then
         return;
      elsif Spread_Bps not in Rate or else Fee_Bps not in Rate then
         Result := Out_Of_Range;
         return;
      elsif Qty_Held < 0 then
         Result := Out_Of_Range;
         return;
      elsif Qty > Qty_Held then
         Result := Insufficient_Holdings;
         return;
      end if;

      declare
         Spread : constant Int64 := Int64 (Spread_Of (Value, Spread_Bps));
         Fee    : constant Int64 := Int64 (Fee_Of (Value, Fee_Bps));
         Costs  : constant Int64 := Spread + Fee;
      begin
         if Costs > Value then
            Result := Negative_Proceeds;
         else
            Quote  := (Value       => Value,
                       Spread      => Spread,
                       Fee         => Fee,
                       Costs       => Costs,
                       Net_Cash_In => Value - Costs);
            Result := Ok;
         end if;
      end;
   end Quote_Sell;

end Ledger_Core.Quotes;
