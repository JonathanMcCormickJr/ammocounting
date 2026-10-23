with Interfaces;

--  Root of the double-entry accounting engine.
--
--  All amounts are integers (cents, centicents, basis points, rounds, Unix
--  seconds); there is no floating point anywhere in this crate. See
--  DESIGN.md for the contract and ABI.md for the C ABI.
package Ledger_Core with SPARK_Mode, Pure is

   type Int32 is new Interfaces.Integer_32;
   type Int64 is new Interfaces.Integer_64;

   --  128-bit type used for intermediate products; never exposed.
   subtype Big is Long_Long_Long_Integer;

   --  Input bounds. Anything outside these is rejected with Out_Of_Range.
   Max_Amount    : constant := 10**12;  --  one posting or trade, in cents
   Max_Quantity  : constant := 10**9;   --  rounds in one trade
   Max_Price     : constant := 10**7;   --  centicents per round
   Max_Bps       : constant := 10_000;  --  100 %
   Max_Aggregate : constant := 10**17;  --  cumulative account totals
   Max_Gain      : constant := 10**18;  --  externally supplied realized gain
   Max_Held      : constant := Max_Quantity;  --  rounds of one caliber held
   Max_Time      : constant := 10**12;  --  Unix seconds, chart sampling
   Max_Size      : constant := 10**9;   --  chart pixels
   Max_Points    : constant := 10**6;   --  chart sample points

   Max_Postings : constant := 16;

   --  Trade side codes (Trade_Buy: units come in, Trade_Sell: units go out).
   Trade_Buy  : constant Int32 := 0;
   Trade_Sell : constant Int32 := 1;

   --  Every engine entry point reports one of these; the representation
   --  values are the codes of the C ABI.
   type Status is
     (Ok,
      Bad_Argument,
      Out_Of_Range,
      Unbalanced,
      Insufficient_Cash,
      Insufficient_Holdings,
      Negative_Proceeds,
      Bad_Order,
      Negative_Balance,
      Not_Reconciled,
      Internal_Error);

   for Status use
     (Ok                    => 0,
      Bad_Argument          => 1,
      Out_Of_Range          => 2,
      Unbalanced            => 3,
      Insufficient_Cash     => 4,
      Insufficient_Holdings => 5,
      Negative_Proceeds     => 6,
      Bad_Order             => 7,
      Negative_Balance      => 8,
      Not_Reconciled        => 9,
      Internal_Error        => 10);

   --  Version as major * 10000 + minor * 100 + patch.
   function Engine_Version return Int32 is (300);

end Ledger_Core;
