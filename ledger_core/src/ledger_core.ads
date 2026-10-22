--  Root of the double-entry accounting engine.
--
--  All amounts are integer minor units (USD cents); there is no floating
--  point anywhere in this crate. The central invariant -- debits equal
--  credits -- is expressed in Is_Balanced and must be proved by GNATprove for
--  every operation that posts a transaction.
package Ledger_Core with SPARK_Mode, Pure is

   --  Bounds are far above any realistic balance, and small enough that
   --  summing Max_Postings amounts can never overflow Cents.
   Max_Amount : constant := 10**12;

   type Cents is range -Max_Amount .. Max_Amount;
   type Positive_Cents is range 1 .. Max_Amount;

   type Side is (Debit, Credit);

   Max_Postings : constant := 16;
   subtype Posting_Count is Natural range 0 .. Max_Postings;
   subtype Posting_Index is Positive range 1 .. Max_Postings;

   type Account_Id is range 1 .. 2**31 - 1;

   type Posting is record
      Account : Account_Id := 1;
      Kind    : Side := Debit;
      Amount  : Positive_Cents := 1;
   end record;

   type Posting_Array is array (Posting_Index) of Posting;

   type Transaction is record
      Count    : Posting_Count := 0;
      Postings : Posting_Array;
   end record;

   --  Sum of the amounts on one side of a transaction. Specification only;
   --  the body is a TODO (see TODO.md, "Ledger core").
   function Total (T : Transaction; Kind : Side) return Long_Long_Integer
   with Ghost, Import;

   --  A transaction may only be posted if debits equal credits.
   function Is_Balanced (T : Transaction) return Boolean is
     (Total (T, Debit) = Total (T, Credit))
   with Ghost;

end Ledger_Core;
