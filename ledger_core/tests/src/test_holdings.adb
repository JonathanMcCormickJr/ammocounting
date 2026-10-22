with Check;
with Ledger_Core.Holdings;
with Ledger_Core.Wire;

procedure Test_Holdings is
   use Ledger_Core;
   use Ledger_Core.Holdings;

   New_Held : Int64;
   Gain     : Int64;
   Total    : Int64;
   Result   : Status;

   procedure Trade (Name : String; Held : Int64; Side : Int32; Qty : Int64;
                    Want : Status; Want_Held : Int64) is
   begin
      Apply_Trade_Quantity (Held, Side, Qty, New_Held, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Eq (Name & " held", New_Held, Want_Held);
   end Trade;

   procedure Total_Of (Name : String; Values : Wire.Int64_Array;
                       Want : Status; Want_Total : Int64) is
   begin
      Sum (Values, Total, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Eq (Name & " total", Total, Want_Total);
   end Total_Of;
begin
   --  Apply_Trade_Quantity
   Trade ("buy 5", 0, 0, 5, Ok, 5);
   Trade ("buy more", 7, 0, 3, Ok, 10);
   Trade ("sell all", 5, 1, 5, Ok, 0);
   Trade ("sell some", 9, 1, 4, Ok, 5);
   Trade ("sell too many", 5, 1, 6, Insufficient_Holdings, 0);
   Trade ("sell from nothing", 0, 1, 1, Insufficient_Holdings, 0);
   Trade ("buy to the limit", Max_Held - 1, 0, 1, Ok, Max_Held);
   Trade ("buy over the limit", Max_Held, 0, 1, Out_Of_Range, 0);
   Trade ("bad side 2", 5, 2, 1, Bad_Argument, 0);
   Trade ("bad side -1", 5, -1, 1, Bad_Argument, 0);
   Trade ("negative held", -1, 0, 1, Out_Of_Range, 0);
   Trade ("held over limit", Max_Held + 1, 1, 1, Out_Of_Range, 0);
   Trade ("zero qty", 5, 0, 0, Out_Of_Range, 0);
   Trade ("qty over limit", 0, 0, Max_Quantity + 1, Out_Of_Range, 0);
   Trade ("sell the maximum", Max_Held, 1, Max_Quantity, Ok, 0);

   --  Portfolio_Position
   Portfolio_Position (25_000, 24_000, Gain, Result);
   Check.Is_Status ("gain ok", Result, Ok);
   Check.Eq ("gain", Gain, 1_000);
   Portfolio_Position (24_000, 25_000, Gain, Result);
   Check.Eq ("loss", Gain, -1_000);
   Portfolio_Position (0, 0, Gain, Result);
   Check.Eq ("flat", Gain, 0);
   Portfolio_Position (Max_Aggregate, 0, Gain, Result);
   Check.Is_Status ("max market", Result, Ok);
   Check.Eq ("max gain", Gain, Max_Aggregate);
   Portfolio_Position (0, Max_Aggregate, Gain, Result);
   Check.Eq ("max loss", Gain, -Max_Aggregate);
   Portfolio_Position (-1, 0, Gain, Result);
   Check.Is_Status ("negative market", Result, Out_Of_Range);
   Check.Eq ("negative market zeroes", Gain, 0);
   Portfolio_Position (0, -1, Gain, Result);
   Check.Is_Status ("negative basis", Result, Out_Of_Range);
   Portfolio_Position (Max_Aggregate + 1, 0, Gain, Result);
   Check.Is_Status ("market over limit", Result, Out_Of_Range);
   Portfolio_Position (0, Max_Aggregate + 1, Gain, Result);
   Check.Is_Status ("basis over limit", Result, Out_Of_Range);

   --  Sum, Sum_To
   Total_Of ("sum", (1, 2, 3), Ok, 6);
   Total_Of ("sum mixed", (-5, 5), Ok, 0);
   Total_Of ("sum negative", (-7, -8), Ok, -15);
   Total_Of ("sum empty", Wire.Int64_Array'(1 .. 0 => 0), Ok, 0);
   Total_Of ("sum limit", (Max_Aggregate, 0), Ok, Max_Aggregate);
   Total_Of ("sum value over", (Max_Aggregate + 1, 0), Out_Of_Range, 0);
   Total_Of ("sum running over", (Max_Aggregate, 1), Out_Of_Range, 0);
   Total_Of ("sum running under", (-Max_Aggregate, -1), Out_Of_Range, 0);
   Total_Of ("sum recovers", (Max_Aggregate, -Max_Aggregate, 5), Ok, 5);
   --  (Sum_To is ghost code: proved, never run.)
end Test_Holdings;
