with Check;
with Ledger_Core.Builders;
with Ledger_Core.Running;
with Ledger_Core.Transactions;
with Ledger_Core.Wire;

procedure Test_Running is
   use Ledger_Core;
   use Ledger_Core.Running;
   use type Wire.Totals;
   use type Wire.Account_Totals;

   Zero : Wire.Totals renames Running.Zero_Totals;

   Deposit_Set : Wire.Posting_Set;
   Buy_Set     : Wire.Posting_Set;
   Sell_Set    : Wire.Posting_Set;
   Gain_Set    : Wire.Posting_Set;
   Loss_Set    : Wire.Posting_Set;
   Info        : Wire.Revaluation;
   Result      : Status;

   After_Deposit : Wire.Totals;
   After_Buy     : Wire.Totals;
   After_Sell    : Wire.Totals;
   After_Gain    : Wire.Totals;
   Next          : Wire.Totals;
   Diff          : Wire.Totals;
   Sums          : Wire.Account_Totals;

   procedure Apply (Name : String; Kind : Int32; Set : Wire.Posting_Set;
                    Prev : Wire.Totals; Want : Status) is
   begin
      Apply_Transaction (Kind, Set, Prev, Next, Result);
      Check.Is_Status (Name, Result, Want);
      if Want /= Ok then
         Check.Holds (Name & " zeroed", Next = Zero);
      end if;
   end Apply;

   --  Debits and credits of one cell.
   procedure Cell (Name : String; T : Wire.Totals; K, A : Integer;
                   Debits, Credits : Int64) is
   begin
      Check.Eq (Name & " debits", T (K, A).Debits, Debits);
      Check.Eq (Name & " credits", T (K, A).Credits, Credits);
   end Cell;

   --  Only the listed cells are non-zero (checked by comparing the sums).
   procedure Only (Name : String; T : Wire.Totals; Debits, Credits : Big) is
   begin
      Check.Eq (Name & " total debits", Total_Debits (T), Debits);
      Check.Eq (Name & " total credits", Total_Credits (T), Credits);
   end Only;
begin
   Builders.Build_Deposit (177_600, Deposit_Set, Result);
   Builders.Build_Buy ((25_000, 125, 250, 375, 25_375), Buy_Set, Result);
   Builders.Build_Sell ((25_000, 125, 250, 375, 24_625), Sell_Set, Result);
   Builders.Revalue (Wire.Int64_Array'(1 => 26_000), 25_000, Info, Gain_Set,
                     Result);
   Builders.Revalue (Wire.Int64_Array'(1 => 24_000), 25_000, Info, Loss_Set,
                     Result);

   --  Apply_Transaction: the running totals through a small life.
   Apply ("deposit", 0, Deposit_Set, Zero, Ok);
   After_Deposit := Next;
   Cell ("deposit cash", After_Deposit, 0, 1, 177_600, 0);
   Cell ("deposit capital", After_Deposit, 0, 3, 0, 177_600);
   Only ("deposit", After_Deposit, 177_600, 177_600);

   Apply ("buy", 1, Buy_Set, After_Deposit, Ok);
   After_Buy := Next;
   Cell ("buy holdings", After_Buy, 1, 2, 25_000, 0);
   Cell ("buy costs", After_Buy, 1, 5, 375, 0);
   Cell ("buy cash", After_Buy, 1, 1, 0, 25_375);
   Cell ("buy keeps deposit", After_Buy, 0, 1, 177_600, 0);
   Only ("buy", After_Buy, 202_975, 202_975);

   Apply ("revalue gain", 3, Gain_Set, After_Buy, Ok);
   After_Gain := Next;
   Cell ("gain holdings", After_Gain, 3, 2, 1_000, 0);
   Cell ("gain income", After_Gain, 3, 4, 0, 1_000);

   Apply ("sell", 2, Sell_Set, After_Gain, Ok);
   After_Sell := Next;
   Cell ("sell cash", After_Sell, 2, 1, 24_625, 0);
   Cell ("sell costs", After_Sell, 2, 5, 375, 0);
   Cell ("sell holdings", After_Sell, 2, 2, 0, 25_000);
   Only ("sell", After_Sell, 228_975, 228_975);

   Apply ("revalue loss", 3, Loss_Set, After_Buy, Ok);
   Cell ("loss income", Next, 3, 4, 1_000, 0);
   Cell ("loss holdings", Next, 3, 2, 0, 1_000);

   --  Apply_Transaction errors
   Apply ("kind 4", 4, Deposit_Set, Zero, Bad_Argument);
   Apply ("kind -1", -1, Deposit_Set, Zero, Bad_Argument);
   Apply ("empty set", 0, Transactions.Empty_Set, Zero, Bad_Argument);
   declare
      Skewed : Wire.Posting_Set := Deposit_Set;
   begin
      Skewed.Items (2).Amount := 177_599;
      Apply ("unbalanced set", 0, Skewed, Zero, Unbalanced);
      Skewed := Deposit_Set;
      Skewed.Items (1).Amount := Max_Amount + 1;
      Skewed.Items (2).Amount := Max_Amount + 1;
      Apply ("amount over max", 0, Skewed, Zero, Out_Of_Range);
   end;
   declare
      Bad : Wire.Totals := Zero;
   begin
      Bad (0, 1).Debits := Max_Cell + 1;
      Apply ("prev cell over max", 0, Deposit_Set, Bad, Out_Of_Range);
      Bad := Zero;
      Bad (0, 1).Debits := -1;
      Apply ("prev cell negative", 0, Deposit_Set, Bad, Out_Of_Range);
      Bad := Zero;
      Bad (0, 1).Debits := 5;
      Apply ("prev unbalanced", 0, Deposit_Set, Bad, Unbalanced);
      Bad := Zero;
      Bad (0, 1).Debits := Max_Cell;
      Bad (0, 3).Credits := Max_Cell;
      Apply ("debit cell overflow", 0, Deposit_Set, Bad, Out_Of_Range);
      Bad := Zero;
      Bad (0, 3).Credits := Max_Cell;
      Bad (0, 1).Debits := Max_Cell;
      Bad (2, 4).Credits := 0;
      declare
         Credit_Heavy : Wire.Posting_Set := Transactions.Empty_Set;
      begin
         Credit_Heavy.Count := 2;
         Credit_Heavy.Items (1) := (1, 0, 1);
         Credit_Heavy.Items (2) := (3, 1, 1);
         Apply ("credit cell overflow", 0, Credit_Heavy, Bad, Out_Of_Range);
      end;
   end;
   Apply ("buy with no cash", 1, Buy_Set, Zero, Negative_Balance);
   Apply ("sell with no holdings", 2, Sell_Set, After_Deposit,
          Negative_Balance);
   Apply ("deposit at the cell limit", 0, Deposit_Set, Zero, Ok);

   --  Diff_Totals
   Diff_Totals (After_Buy, After_Deposit, Diff, Result);
   Check.Is_Status ("diff", Result, Ok);
   Cell ("diff holdings", Diff, 1, 2, 25_000, 0);
   Cell ("diff cash", Diff, 1, 1, 0, 25_375);
   Cell ("diff deposit gone", Diff, 0, 1, 0, 0);
   Only ("diff", Diff, 25_375, 25_375);
   Diff_Totals (After_Buy, After_Buy, Diff, Result);
   Check.Is_Status ("diff equal", Result, Ok);
   Check.Holds ("diff equal is zero", Diff = Zero);
   Diff_Totals (After_Buy, Zero, Diff, Result);
   Check.Holds ("diff from zero", Diff = After_Buy);
   Diff_Totals (After_Deposit, After_Buy, Diff, Result);
   Check.Is_Status ("diff backwards", Result, Bad_Order);
   Check.Holds ("diff backwards zeroed", Diff = Zero);
   declare
      Bad : Wire.Totals := Zero;
   begin
      Bad (1, 1).Credits := Max_Cell + 1;
      Diff_Totals (Bad, Zero, Diff, Result);
      Check.Is_Status ("diff invalid to", Result, Out_Of_Range);
      Diff_Totals (Zero, Bad, Diff, Result);
      Check.Is_Status ("diff invalid from", Result, Out_Of_Range);
      Bad := Zero;
      Bad (1, 1).Credits := 3;
      Diff_Totals (Bad, Zero, Diff, Result);
      Check.Is_Status ("diff unbalanced to", Result, Unbalanced);
      Diff_Totals (After_Buy, Bad, Diff, Result);
      Check.Is_Status ("diff unbalanced from", Result, Unbalanced);
   end;

   --  Collapse_Kinds
   Collapse_Kinds (After_Sell, Sums, Result);
   Check.Is_Status ("collapse", Result, Ok);
   Check.Eq ("collapse cash debits", Sums (1).Debits, 177_600 + 24_625);
   Check.Eq ("collapse cash credits", Sums (1).Credits, 25_375);
   Check.Eq ("collapse holdings debits", Sums (2).Debits, 26_000);
   Check.Eq ("collapse holdings credits", Sums (2).Credits, 25_000);
   Check.Eq ("collapse capital credits", Sums (3).Credits, 177_600);
   Check.Eq ("collapse income credits", Sums (4).Credits, 1_000);
   Check.Eq ("collapse costs debits", Sums (5).Debits, 750);
   declare
      Many : Wire.Totals := Zero;
   begin
      Many (0, 1).Debits := Max_Cell;
      Many (1, 1).Debits := Max_Cell;
      Many (2, 1).Debits := Max_Cell;
      Many (3, 1).Debits := Max_Cell;
      Collapse_Kinds (Many, Sums, Result);
      Check.Is_Status ("collapse four full cells", Result, Ok);
      Check.Eq ("collapse four full cells sum", Sums (1).Debits,
                Max_Aggregate);
      Many (3, 5).Credits := Max_Cell + 1;
      Collapse_Kinds (Many, Sums, Result);
      Check.Is_Status ("collapse invalid", Result, Out_Of_Range);
      Check.Holds ("collapse invalid zeroed", Sums = (1 .. 5 => (0, 0)));
   end;

   --  Valid, Account_Debits, Account_Credits, Total_*, Balanced,
   --  Books_Sound, Not_Less
   Check.Holds ("zero is valid", Valid (Zero));
   Check.Holds ("after buy valid", Valid (After_Buy));
   Check.Eq ("account debits sum kinds", Account_Debits (After_Sell, 1),
             202_225);
   Check.Eq ("account credits sum kinds", Account_Credits (After_Sell, 2),
             25_000);
   Check.Holds ("balanced", Balanced (After_Sell));
   Check.Holds ("books sound", Books_Sound (After_Sell));
   declare
      Bad : Wire.Totals := Zero;
   begin
      Bad (0, 1).Debits := 1;
      Check.Holds ("unbalanced", not Balanced (Bad));
      Bad := Zero;
      Bad (0, 1).Credits := 1;
      Bad (0, 3).Debits := 1;
      Check.Holds ("negative cash unsound", not Books_Sound (Bad));
      Bad := Zero;
      Bad (0, 2).Credits := 1;
      Bad (0, 3).Debits := 1;
      Check.Holds ("negative holdings unsound", not Books_Sound (Bad));
      Bad := Zero;
      Bad (2, 5).Debits := Max_Cell + 1;
      Check.Holds ("over max invalid", not Valid (Bad));
      Bad := Zero;
      Bad (2, 5).Credits := -1;
      Check.Holds ("negative invalid", not Valid (Bad));
   end;
   Check.Holds ("not less: later", Not_Less (After_Buy, After_Deposit));
   Check.Holds ("not less: equal", Not_Less (After_Buy, After_Buy));
   Check.Holds ("not less: earlier", not Not_Less (After_Deposit, After_Buy));

   --  Audit_Chain
   Audit_Chain (Wire.Totals_Array'(After_Deposit, After_Buy, After_Gain),
                Result);
   Check.Is_Status ("chain ok", Result, Ok);
   Audit_Chain (Wire.Totals_Array'(1 .. 0 => Zero), Result);
   Check.Is_Status ("chain empty", Result, Ok);
   Audit_Chain (Wire.Totals_Array'(1 => After_Buy), Result);
   Check.Is_Status ("chain of one", Result, Ok);
   Audit_Chain (Wire.Totals_Array'(After_Buy, After_Deposit), Result);
   Check.Is_Status ("chain goes back", Result, Bad_Order);
   declare
      Bad : Wire.Totals := Zero;
   begin
      Bad (0, 1).Debits := Max_Cell + 1;
      Audit_Chain (Wire.Totals_Array'(After_Deposit, Bad), Result);
      Check.Is_Status ("chain invalid row", Result, Out_Of_Range);
      Bad := Zero;
      Bad (0, 1).Debits := 1;
      Audit_Chain (Wire.Totals_Array'(After_Deposit, Bad), Result);
      Check.Is_Status ("chain unbalanced row", Result, Unbalanced);
      Bad := Zero;
      Bad (0, 1).Credits := 1;
      Bad (0, 3).Debits := 1;
      Audit_Chain (Wire.Totals_Array'(1 => Bad), Result);
      Check.Is_Status ("chain unsound row", Result, Negative_Balance);
   end;
end Test_Running;
