with Check;
with Ledger_Core.Transactions;
with Ledger_Core.Wire;

procedure Test_Transactions is
   use Ledger_Core;
   use Ledger_Core.Transactions;

   Deposit : constant Wire.Posting_Array :=
     ((1, 0, 177_600), (3, 1, 177_600));

   Buy : constant Wire.Posting_Array :=
     ((2, 0, 25_000), (5, 0, 375), (1, 1, 25_375));

   Result : Status;

   procedure Expect (Name : String; P : Wire.Posting_Array; Want : Status) is
   begin
      Validate (P, Result);
      Check.Is_Status (Name, Result, Want);
   end Expect;
begin
   --  Well_Formed
   Check.Holds ("well formed", Well_Formed ((1, 0, 1)));
   Check.Holds ("account 0", not Well_Formed ((0, 0, 1)));
   Check.Holds ("account 6", not Well_Formed ((6, 0, 1)));
   Check.Holds ("side 2", not Well_Formed ((1, 2, 1)));
   Check.Holds ("amount 0", not Well_Formed ((1, 0, 0)));
   Check.Holds ("amount max", Well_Formed ((5, 1, Max_Amount)));
   Check.Holds ("amount over max", not Well_Formed ((5, 1, Max_Amount + 1)));

   --  Total
   Check.Eq ("buy debits", Total (Buy, Debit), 25_375);
   Check.Eq ("buy credits", Total (Buy, Credit), 25_375);
   Check.Eq ("deposit debits", Total (Deposit, Debit), 177_600);
   Check.Eq ("no postings", Total (Wire.Posting_Array'(1 .. 0 => <>), Debit),
             0);

   --  Validate
   Expect ("deposit balances", Deposit, Ok);
   Expect ("buy balances", Buy, Ok);
   Expect ("one posting is unbalanced", (1 => (1, 0, 5)), Unbalanced);
   Expect ("unbalanced by one cent",
           ((1, 0, 100), (3, 1, 99)), Unbalanced);
   Expect ("empty", Wire.Posting_Array'(1 .. 0 => <>), Bad_Argument);
   Expect ("account 0", ((0, 0, 5), (3, 1, 5)), Bad_Argument);
   Expect ("account 6", ((6, 0, 5), (3, 1, 5)), Bad_Argument);
   Expect ("side 2", ((1, 2, 5), (3, 1, 5)), Bad_Argument);
   Expect ("amount zero", ((1, 0, 0), (3, 1, 0)), Bad_Argument);
   Expect ("amount negative", ((1, 0, -5), (3, 1, -5)), Bad_Argument);
   Expect ("amount over max",
           ((1, 0, Max_Amount + 1), (3, 1, Max_Amount + 1)), Out_Of_Range);
   Expect ("amount exactly max",
           ((1, 0, Max_Amount), (3, 1, Max_Amount)), Ok);

   declare
      Full : Wire.Posting_Array (1 .. 16) :=
        (others => (1, 0, 10));
      Over : constant Wire.Posting_Array (1 .. 17) := (others => (1, 0, 10));
   begin
      for I in 9 .. 16 loop
         Full (I) := (3, 1, 10);
      end loop;
      Expect ("sixteen postings", Full, Ok);
      Expect ("seventeen postings", Over, Bad_Argument);
      Full (16).Amount := 11;
      Expect ("sixteen unbalanced", Full, Unbalanced);
   end;

   --  Side_To / Posted_To / Posted (prefix sums, ghost-free)
   Check.Eq ("side_to no postings", Side_To (Buy, 0, Debit), 0);
   Check.Eq ("side_to first posting debit", Side_To (Buy, 1, Debit), 25_000);
   Check.Eq ("side_to two postings debit", Side_To (Buy, 2, Debit), 25_375);
   Check.Eq ("side_to all postings credit", Side_To (Buy, 3, Credit), 25_375);
   Check.Eq ("side_to prefix has no credit", Side_To (Buy, 2, Credit), 0);
   Check.Eq ("posted_to holdings debit", Posted_To (Buy, 3, 2, Debit), 25_000);
   Check.Eq ("posted_to costs debit", Posted_To (Buy, 3, 5, Debit), 375);
   Check.Eq ("posted_to cash credit", Posted_To (Buy, 3, 1, Credit), 25_375);
   Check.Eq ("posted_to cash debit", Posted_To (Buy, 3, 1, Debit), 0);
   Check.Eq ("posted_to prefix", Posted_To (Buy, 1, 5, Debit), 0);
   Check.Eq ("posted capital credit", Posted (Deposit, 3, Credit), 177_600);
   Check.Eq ("posted two lines same account",
             Posted (Wire.Posting_Array'((1, 0, 5), (1, 0, 7), (3, 1, 12)),
                     1, Debit), 12);

   --  Posts_Exactly (ghost)
   pragma Assert
     (Posts_Exactly (Deposit, (1 => 177_600, others => 0),
                     (3 => 177_600, others => 0)));
   pragma Assert
     (not Posts_Exactly (Deposit, (1 => 177_600, others => 0),
                         (3 => 177_599, others => 0)));
   pragma Assert
     (not Posts_Exactly (Deposit, (1 => 177_600, 2 => 1, others => 0),
                         (3 => 177_600, others => 0)));
   Check.Holds ("posts exactly", True);

   --  Postings_Of / Valid_Set / Validate_Set / Empty_Set
   declare
      Set  : Wire.Posting_Set := Empty_Set;
      Rows : Wire.Posting_Array (1 .. 2);
   begin
      Check.Eq ("empty set count", Set.Count, 0);
      Check.Holds ("empty set is not valid", not Valid_Set (Set));
      Validate_Set (Set, Result);
      Check.Is_Status ("empty set", Result, Bad_Argument);
      Set.Count := 2;
      Set.Items (1) := (1, 0, 5);
      Set.Items (2) := (3, 1, 5);
      Rows := Postings_Of (Set);
      Check.Eq ("postings of length", Int32 (Rows'Length), 2);
      Check.Eq ("postings of first", Rows (1).Amount, 5);
      Check.Eq ("postings of second account", Rows (2).Account, 3);
      Check.Holds ("balanced set is valid", Valid_Set (Set));
      Validate_Set (Set, Result);
      Check.Is_Status ("balanced set", Result, Ok);
      Set.Items (2).Amount := 4;
      Check.Holds ("unbalanced set is not valid", not Valid_Set (Set));
      Validate_Set (Set, Result);
      Check.Is_Status ("unbalanced set", Result, Unbalanced);
      Set.Items (2) := (3, 1, 5);
      Set.Items (1).Account := 9;
      Check.Holds ("bad account set is not valid", not Valid_Set (Set));
      Validate_Set (Set, Result);
      Check.Is_Status ("bad account set", Result, Bad_Argument);
      Set.Items (1) := (1, 0, Max_Amount + 1);
      Set.Items (2) := (3, 1, Max_Amount + 1);
      Validate_Set (Set, Result);
      Check.Is_Status ("over max set", Result, Out_Of_Range);
      Set.Count := 17;
      Validate_Set (Set, Result);
      Check.Is_Status ("count 17", Result, Bad_Argument);
      Set.Count := -1;
      Validate_Set (Set, Result);
      Check.Is_Status ("count -1", Result, Bad_Argument);
      Check.Holds ("count -1 is not valid", not Valid_Set (Set));
   end;
end Test_Transactions;
