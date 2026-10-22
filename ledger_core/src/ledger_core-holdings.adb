package body Ledger_Core.Holdings with SPARK_Mode is

   procedure Apply_Trade_Quantity
     (Held     : Int64;
      Side     : Int32;
      Qty      : Int64;
      New_Held : out Int64;
      Result   : out Status)
   is
   begin
      New_Held := 0;
      if Side not in Trade_Buy .. Trade_Sell then
         Result := Bad_Argument;
      elsif Held not in Held_Quantity or else Qty not in 1 .. Max_Quantity then
         Result := Out_Of_Range;
      elsif Side = Trade_Buy then
         if Held + Qty > Max_Held then
            Result := Out_Of_Range;
         else
            New_Held := Held + Qty;
            Result   := Ok;
         end if;
      elsif Qty > Held then
         Result := Insufficient_Holdings;
      else
         New_Held := Held - Qty;
         Result   := Ok;
      end if;
   end Apply_Trade_Quantity;

   procedure Portfolio_Position
     (Market_Value : Int64;
      Cost_Basis   : Int64;
      Gain         : out Int64;
      Result       : out Status)
   is
   begin
      if Market_Value in Aggregate and then Cost_Basis in Aggregate then
         Gain   := Market_Value - Cost_Basis;
         Result := Ok;
      else
         Gain   := 0;
         Result := Out_Of_Range;
      end if;
   end Portfolio_Position;

   procedure Sum
     (Values : Wire.Int64_Array;
      Total  : out Int64;
      Result : out Status)
   is
      Running : Int64 := 0;
   begin
      Total  := 0;
      Result := Ok;
      for I in Values'Range loop
         pragma Loop_Invariant (Running in Signed_Aggregate);
         pragma Loop_Invariant
           (Big (Running) = Sum_To (Values, I - Values'First));
         if Values (I) not in Signed_Aggregate
           or else Running + Values (I) not in Signed_Aggregate
         then
            Result := Out_Of_Range;
            return;
         end if;
         Running := Running + Values (I);
      end loop;
      Total := Running;
   end Sum;

end Ledger_Core.Holdings;
