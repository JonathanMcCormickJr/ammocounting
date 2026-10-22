with Ledger_Core.Transactions;
with Ledger_Core.Wire;

--  Running totals: cumulative debits and credits per transaction kind and
--  account. Every ledger transaction row stores the totals as of that row, so
--  a balance as of time T is read from one row and never summed from
--  postings. Kinds: 0 deposit, 1 buy, 2 sell, 3 revalue. Accounts as in
--  Transactions. On any non-Ok status every output is zero.
package Ledger_Core.Running with SPARK_Mode is

   use type Wire.Totals;
   use type Wire.Account_Totals;

   subtype Kind_Code is Int32 range 0 .. 3;

   --  Each cell is at most a quarter of Max_Aggregate, so that the four kinds
   --  of one account always sum to at most Max_Aggregate.
   Max_Cell : constant := Max_Aggregate / 4;

   Zero_Totals : constant Wire.Totals := (others => (others => (0, 0)));

   function Valid (T : Wire.Totals) return Boolean
   is (for all K in 0 .. 3 =>
         (for all A in 1 .. 5 =>
            T (K, A).Debits in 0 .. Max_Cell
            and then T (K, A).Credits in 0 .. Max_Cell));

   --  Debits (or credits) of one account over the four kinds.
   function Account_Debits (T : Wire.Totals; A : Transactions.Account_Code)
      return Big
   is (Big (T (0, Integer (A)).Debits) + Big (T (1, Integer (A)).Debits)
       + Big (T (2, Integer (A)).Debits) + Big (T (3, Integer (A)).Debits));

   function Account_Credits (T : Wire.Totals; A : Transactions.Account_Code)
      return Big
   is (Big (T (0, Integer (A)).Credits) + Big (T (1, Integer (A)).Credits)
       + Big (T (2, Integer (A)).Credits) + Big (T (3, Integer (A)).Credits));

   function Total_Debits (T : Wire.Totals) return Big
   is (Account_Debits (T, 1) + Account_Debits (T, 2) + Account_Debits (T, 3)
       + Account_Debits (T, 4) + Account_Debits (T, 5));

   function Total_Credits (T : Wire.Totals) return Big
   is (Account_Credits (T, 1) + Account_Credits (T, 2)
       + Account_Credits (T, 3) + Account_Credits (T, 4)
       + Account_Credits (T, 5));

   --  Global invariant: total debits equal total credits.
   function Balanced (T : Wire.Totals) return Boolean
   is (Total_Debits (T) = Total_Credits (T));

   --  Cash and Holdings never hold a negative balance.
   function Books_Sound (T : Wire.Totals) return Boolean
   is (Account_Debits (T, Transactions.Cash_Account)
         >= Account_Credits (T, Transactions.Cash_Account)
       and then Account_Debits (T, Transactions.Holdings_Account)
                  >= Account_Credits (T, Transactions.Holdings_Account));

   --  Every cell of A is at least the same cell of B.
   function Not_Less (A, B : Wire.Totals) return Boolean
   is (for all K in 0 .. 3 =>
         (for all Acct in 1 .. 5 =>
            A (K, Acct).Debits >= B (K, Acct).Debits
            and then A (K, Acct).Credits >= B (K, Acct).Credits));

   --  Adds the postings of Set to Prev under Kind. Checks, in order: Kind in
   --  0 .. 3 and the set valid (Bad_Argument, Out_Of_Range, Unbalanced as in
   --  Transactions.Validate_Set); Prev valid (Out_Of_Range) and balanced
   --  (Unbalanced); no cell above Max_Cell (Out_Of_Range); cash and holdings
   --  not negative afterwards (Negative_Balance). When Ok, every cell of
   --  Next equals the same cell of Prev plus exactly what the postings put
   --  on that account and side (for the posted Kind only), and Next is valid
   --  and balanced.
   procedure Apply_Transaction
     (Kind   : Int32;
      Set    : Wire.Posting_Set;
      Prev   : Wire.Totals;
      Next   : out Wire.Totals;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Kind in Kind_Code
          and then Transactions.Valid_Set (Set)
          and then Valid (Prev)
          and then Balanced (Prev)
          and then Valid (Next)
          and then Balanced (Next)
          and then Books_Sound (Next)
          and then
            (for all K in 0 .. 3 =>
               (for all A in 1 .. 5 =>
                  Big (Next (K, A).Debits) =
                    Big (Prev (K, A).Debits)
                    + (if Int32 (K) = Kind
                       then Transactions.Posted
                              (Transactions.Postings_Of (Set),
                               Transactions.Account_Code (A),
                               Transactions.Debit)
                       else 0)
                  and then Big (Next (K, A).Credits) =
                    Big (Prev (K, A).Credits)
                    + (if Int32 (K) = Kind
                       then Transactions.Posted
                              (Transactions.Postings_Of (Set),
                               Transactions.Account_Code (A),
                               Transactions.Credit)
                       else 0)))
        else Next = Zero_Totals);

   --  Period activity: Diff = To - From, cell by cell. Both must be valid
   --  (Out_Of_Range) and balanced (Unbalanced), and To must not be below From
   --  in any cell (Bad_Order). When Ok, Diff is valid, balanced, and
   --  non-negative.
   procedure Diff_Totals
     (To     : Wire.Totals;
      From   : Wire.Totals;
      Diff   : out Wire.Totals;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Valid (To) and then Valid (From)
          and then Balanced (To) and then Balanced (From)
          and then Not_Less (To, From)
          and then Valid (Diff)
          and then Balanced (Diff)
          and then
            (for all K in 0 .. 3 =>
               (for all A in 1 .. 5 =>
                  Diff (K, A).Debits = To (K, A).Debits - From (K, A).Debits
                  and then
                    Diff (K, A).Credits =
                      To (K, A).Credits - From (K, A).Credits))
        else Diff = Zero_Totals);

   --  Sums the four kinds of every account into the five-account totals used
   --  by Balance_Sheet and Income_Statement. Totals must be valid.
   procedure Collapse_Kinds
     (Totals    : Wire.Totals;
      Collapsed : out Wire.Account_Totals;
      Result    : out Status)
   with
     Post =>
       (if Result = Ok then
          Valid (Totals)
          and then
            (for all A in 1 .. 5 =>
               Big (Collapsed (A).Debits) =
                 Account_Debits (Totals, Transactions.Account_Code (A))
               and then
                 Big (Collapsed (A).Credits) =
                   Account_Credits (Totals, Transactions.Account_Code (A))
               and then Collapsed (A).Debits in 0 .. Max_Aggregate
               and then Collapsed (A).Credits in 0 .. Max_Aggregate)
        else Collapsed = (1 .. 5 => (0, 0)));

   --  Verifies a chain of stored rows, oldest first: every row valid
   --  (Out_Of_Range), balanced (Unbalanced) with sound books
   --  (Negative_Balance), and no row below its predecessor (Bad_Order).
   procedure Audit_Chain (Rows : Wire.Totals_Array; Result : out Status)
   with
     Post =>
       (if Result = Ok then
          (for all I in Rows'Range =>
             Valid (Rows (I)) and then Balanced (Rows (I))
             and then Books_Sound (Rows (I))
             and then (if I > Rows'First then
                         Not_Less (Rows (I), Rows (I - 1)))));

end Ledger_Core.Running;
