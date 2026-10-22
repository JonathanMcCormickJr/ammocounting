with Check;
with Ledger_Core.Builders;
with Ledger_Core.Transactions;
with Ledger_Core.Wire;

procedure Test_Builders is
   use Ledger_Core;
   use Ledger_Core.Builders;
   use type Wire.Posting_Set;
   use type Wire.Posting;
   use type Wire.Revaluation;

   Set    : Wire.Posting_Set;
   Info   : Wire.Revaluation;
   Result : Status;

   function P (Account, Side : Int32; Amount : Int64) return Wire.Posting
   is ((Account, Side, Amount));

   --  The set has exactly these postings (in order) and is valid.
   procedure Is_Set (Name : String; Want : Wire.Posting_Array) is
   begin
      Check.Eq (Name & " count", Set.Count, Int32 (Want'Length));
      Check.Eq (Name & " reserved", Set.Reserved, 0);
      for I in Want'Range loop
         Check.Holds (Name & " posting" & Integer'Image (I),
                      Set.Items (I) = Want (I));
      end loop;
      Check.Holds (Name & " valid", Transactions.Valid_Set (Set));
   end Is_Set;

   procedure Is_Empty (Name : String) is
   begin
      Check.Holds (Name & " zeroed", Set = Transactions.Empty_Set);
   end Is_Empty;

   Zero_Info : constant Wire.Revaluation := (0, 0, 0, 0);
begin
   --  Consistent_Buy / Consistent_Sell
   Check.Holds ("buy consistent",
                Consistent_Buy ((25_000, 125, 250, 375, 25_375)));
   Check.Holds ("buy costs differ",
                not Consistent_Buy ((25_000, 125, 250, 376, 25_376)));
   Check.Holds ("buy total differs",
                not Consistent_Buy ((25_000, 125, 250, 375, 25_376)));
   Check.Holds ("buy part negative",
                not Consistent_Buy ((25_000, -125, 500, 375, 25_375)));
   Check.Holds ("buy part over max",
                not Consistent_Buy
                  ((Max_Amount + 1, 0, 0, 0, Max_Amount + 1)));
   Check.Holds ("sell consistent",
                Consistent_Sell ((25_000, 125, 250, 375, 24_625)));
   Check.Holds ("sell net differs",
                not Consistent_Sell ((25_000, 125, 250, 375, 24_626)));
   Check.Holds ("sell costs differ",
                not Consistent_Sell ((25_000, 125, 250, 374, 24_626)));
   Check.Holds ("sell part negative",
                not Consistent_Sell ((25_000, 125, 250, 375, -1)));

   --  Build_Deposit
   Build_Deposit (177_600, Set, Result);
   Check.Is_Status ("deposit", Result, Ok);
   Is_Set ("deposit", (P (1, 0, 177_600), P (3, 1, 177_600)));
   Build_Deposit (Max_Amount, Set, Result);
   Check.Is_Status ("deposit max", Result, Ok);
   Build_Deposit (0, Set, Result);
   Check.Is_Status ("deposit zero", Result, Bad_Argument);
   Is_Empty ("deposit zero");
   Build_Deposit (-5, Set, Result);
   Check.Is_Status ("deposit negative", Result, Bad_Argument);
   Build_Deposit (Max_Amount + 1, Set, Result);
   Check.Is_Status ("deposit over max", Result, Out_Of_Range);
   Is_Empty ("deposit over max");

   --  Build_Buy
   Build_Buy ((25_000, 125, 250, 375, 25_375), Set, Result);
   Check.Is_Status ("buy", Result, Ok);
   Is_Set ("buy", (P (2, 0, 25_000), P (5, 0, 375), P (1, 1, 25_375)));
   Build_Buy ((3, 0, 0, 0, 3), Set, Result);
   Check.Is_Status ("buy no costs", Result, Ok);
   Is_Set ("buy no costs", (P (2, 0, 3), P (1, 1, 3)));
   Build_Buy ((0, 5, 0, 5, 5), Set, Result);
   Check.Is_Status ("buy only costs", Result, Ok);
   Is_Set ("buy only costs", (P (5, 0, 5), P (1, 1, 5)));
   Build_Buy ((0, 0, 0, 0, 0), Set, Result);
   Check.Is_Status ("buy nothing", Result, Bad_Argument);
   Is_Empty ("buy nothing");
   Build_Buy ((25_000, 125, 250, 376, 25_376), Set, Result);
   Check.Is_Status ("buy costs differ", Result, Unbalanced);
   Is_Empty ("buy costs differ");
   Build_Buy ((25_000, 125, 250, 375, 25_000), Set, Result);
   Check.Is_Status ("buy total differs", Result, Unbalanced);
   Build_Buy ((Max_Amount + 1, 0, 0, 0, Max_Amount + 1), Set, Result);
   Check.Is_Status ("buy value over max", Result, Out_Of_Range);
   Build_Buy ((-1, 0, 0, 0, -1), Set, Result);
   Check.Is_Status ("buy negative", Result, Out_Of_Range);

   --  Build_Sell
   Build_Sell ((25_000, 125, 250, 375, 24_625), Set, Result);
   Check.Is_Status ("sell", Result, Ok);
   Is_Set ("sell", (P (1, 0, 24_625), P (5, 0, 375), P (2, 1, 25_000)));
   Build_Sell ((100, 100, 0, 100, 0), Set, Result);
   Check.Is_Status ("sell no proceeds", Result, Ok);
   Is_Set ("sell no proceeds", (P (5, 0, 100), P (2, 1, 100)));
   Build_Sell ((3, 0, 0, 0, 3), Set, Result);
   Check.Is_Status ("sell no costs", Result, Ok);
   Is_Set ("sell no costs", (P (1, 0, 3), P (2, 1, 3)));
   Build_Sell ((0, 0, 0, 0, 0), Set, Result);
   Check.Is_Status ("sell nothing", Result, Bad_Argument);
   Is_Empty ("sell nothing");
   Build_Sell ((25_000, 125, 250, 375, 24_626), Set, Result);
   Check.Is_Status ("sell net differs", Result, Unbalanced);
   Build_Sell ((25_000, 125, 250, 374, 24_626), Set, Result);
   Check.Is_Status ("sell costs differ", Result, Unbalanced);
   Build_Sell ((Max_Amount + 1, 0, 0, 0, Max_Amount + 1), Set, Result);
   Check.Is_Status ("sell over max", Result, Out_Of_Range);

   --  Revalue
   Revalue ((100, 200), 250, Info, Set, Result);
   Check.Is_Status ("revalue gain", Result, Ok);
   Check.Holds ("revalue gain info", Info = (300, 50, Gained, 0));
   Is_Set ("revalue gain", (P (2, 0, 50), P (4, 1, 50)));
   Revalue ((100, 200), 400, Info, Set, Result);
   Check.Is_Status ("revalue loss", Result, Ok);
   Check.Holds ("revalue loss info", Info = (300, 100, Lost, 0));
   Is_Set ("revalue loss", (P (4, 0, 100), P (2, 1, 100)));
   Revalue ((100, 200), 300, Info, Set, Result);
   Check.Is_Status ("revalue equal", Result, Ok);
   Check.Holds ("revalue equal info", Info = (300, 0, 0, 0));
   Is_Empty ("revalue equal");
   Revalue (Wire.Int64_Array'(1 .. 0 => 0), 0, Info, Set, Result);
   Check.Is_Status ("revalue nothing held", Result, Ok);
   Check.Holds ("revalue nothing info", Info = Zero_Info);
   Revalue (Wire.Int64_Array'(1 .. 0 => 0), 5, Info, Set, Result);
   Check.Is_Status ("revalue to nothing", Result, Ok);
   Check.Holds ("revalue to nothing info", Info = (0, 5, Lost, 0));
   Revalue ((Max_Amount + 1, 0), 0, Info, Set, Result);
   Check.Is_Status ("revalue value over max", Result, Out_Of_Range);
   Check.Holds ("revalue error zeroes info", Info = Zero_Info);
   Is_Empty ("revalue error");
   Revalue ((-1, 0), 0, Info, Set, Result);
   Check.Is_Status ("revalue negative value", Result, Out_Of_Range);
   Revalue ((1 => 5), -1, Info, Set, Result);
   Check.Is_Status ("revalue negative carrying", Result, Out_Of_Range);
   Revalue ((1 => 5), Max_Aggregate + 1, Info, Set, Result);
   Check.Is_Status ("revalue carrying over", Result, Out_Of_Range);
   Revalue ((Max_Amount, Max_Amount), 0, Info, Set, Result);
   Check.Is_Status ("revalue difference over max", Result, Out_Of_Range);
   Revalue ((1 => 0), 2 * Max_Amount, Info, Set, Result);
   Check.Is_Status ("revalue loss over max", Result, Out_Of_Range);
   declare
      Many : constant Wire.Int64_Array (1 .. 100_001) :=
        (others => Max_Amount);
   begin
      Revalue (Many (1 .. 100_000), Max_Aggregate, Info, Set, Result);
      Check.Is_Status ("revalue sum at limit", Result, Ok);
      Check.Eq ("revalue sum at limit total", Info.Market_Total,
                Max_Aggregate);
      Revalue (Many, 0, Info, Set, Result);
      Check.Is_Status ("revalue sum over limit", Result, Out_Of_Range);
   end;
end Test_Builders;
