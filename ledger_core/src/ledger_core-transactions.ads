with Ledger_Core.Wire;

package Ledger_Core.Transactions with SPARK_Mode is

   subtype Account_Code is Int32 range 1 .. 5;
   subtype Side_Code is Int32 range 0 .. 1;
   subtype Amount is Int64 range 1 .. Max_Amount;

   Cash_Account     : constant Account_Code := 1;
   Holdings_Account : constant Account_Code := 2;
   Capital_Account  : constant Account_Code := 3;
   Gain_Account     : constant Account_Code := 4;
   Costs_Account    : constant Account_Code := 5;

   Debit  : constant Side_Code := 0;
   Credit : constant Side_Code := 1;

   function Well_Formed (P : Wire.Posting) return Boolean is
     (P.Account in Account_Code
      and then P.Side in Side_Code
      and then P.Amount in Amount);

   --  Sum of the amounts posted on one side by the first K postings. Only
   --  meaningful (and only bounded) when every posting is well formed.
   function Side_To
     (Postings : Wire.Posting_Array; K : Natural; Side : Side_Code)
      return Big
   is
     (if K = 0 then 0
      else Side_To (Postings, K - 1, Side)
           + (if Postings (Postings'First + (K - 1)).Side = Side
              then Big (Postings (Postings'First + (K - 1)).Amount)
              else 0))
   with
     Pre                =>
       K <= Postings'Length
       and then (for all P of Postings => Well_Formed (P)),
     Post               => Side_To'Result in 0 .. Big (K) * Max_Amount,
     Subprogram_Variant => (Decreases => K);

   --  Sum of the amounts the first K postings put on one side of one account.
   function Posted_To
     (Postings : Wire.Posting_Array;
      K        : Natural;
      Account  : Account_Code;
      Side     : Side_Code) return Big
   is
     (if K = 0 then 0
      else Posted_To (Postings, K - 1, Account, Side)
           + (if Postings (Postings'First + (K - 1)).Account = Account
                 and then Postings (Postings'First + (K - 1)).Side = Side
              then Big (Postings (Postings'First + (K - 1)).Amount)
              else 0))
   with
     Pre                =>
       K <= Postings'Length
       and then (for all P of Postings => Well_Formed (P)),
     Post               => Posted_To'Result in 0 .. Big (K) * Max_Amount,
     Subprogram_Variant => (Decreases => K);

   --  Sum of the amounts posted on one side.
   function Total
     (Postings : Wire.Posting_Array; Side : Side_Code) return Big
   is (Side_To (Postings, Postings'Length, Side))
   with
     Pre  =>
       Postings'Length <= Max_Postings
       and then (for all P of Postings => Well_Formed (P)),
     Post => Total'Result in 0 .. Big (Max_Postings) * Max_Amount;

   --  Sum of the amounts posted on one side of one account.
   function Posted
     (Postings : Wire.Posting_Array; Account : Account_Code; Side : Side_Code)
      return Big
   is (Posted_To (Postings, Postings'Length, Account, Side))
   with
     Pre  =>
       Postings'Length <= Max_Postings
       and then (for all P of Postings => Well_Formed (P)),
     Post => Posted'Result in 0 .. Big (Max_Postings) * Max_Amount;

   --  Amounts per account, used to state exactly what a transaction posts.
   type Profile is array (Account_Code) of Big;

   --  The postings put exactly Debits (A) on the debit side and Credits (A)
   --  on the credit side of every account A, and nothing else.
   function Posts_Exactly
     (Postings : Wire.Posting_Array; Debits, Credits : Profile) return Boolean
   is
     (for all A in Account_Code =>
        Posted (Postings, A, Debit) = Debits (A)
        and then Posted (Postings, A, Credit) = Credits (A))
   with
     Ghost,
     Pre =>
       Postings'Length <= Max_Postings
       and then (for all P of Postings => Well_Formed (P));

   --  Ok exactly when there are 1 .. 16 well-formed postings and total
   --  debits equal total credits.
   procedure Validate
     (Postings : Wire.Posting_Array; Result : out Status)
   with
     Post =>
       (Result = Ok) =
         (Postings'Length in 1 .. Max_Postings
          and then (for all P of Postings => Well_Formed (P))
          and then Total (Postings, Debit) = Total (Postings, Credit));

   --  The postings of a set (its first Count items).
   function Postings_Of (S : Wire.Posting_Set) return Wire.Posting_Array
   is (Wire.Posting_Array (S.Items (1 .. Integer (S.Count))))
   with
     Pre  => S.Count in 0 .. Max_Postings,
     Post => Postings_Of'Result'Length = Natural (S.Count)
             and then Postings_Of'Result'First = 1;

   --  A set is valid when its postings pass Validate.
   function Valid_Set (S : Wire.Posting_Set) return Boolean
   is (S.Count in 1 .. Max_Postings
       and then (for all I in 1 .. Integer (S.Count) =>
                   Well_Formed (S.Items (I)))
       and then Total (Postings_Of (S), Debit)
                = Total (Postings_Of (S), Credit));

   --  Ok exactly when Valid_Set; Count outside 1 .. 16 is Bad_Argument.
   procedure Validate_Set (S : Wire.Posting_Set; Result : out Status)
   with Post => (Result = Ok) = Valid_Set (S);

   --  The all-zero set (what builders return on failure).
   Empty_Set : constant Wire.Posting_Set :=
     (Count => 0, Reserved => 0, Items => (others => (0, 0, 0)));

end Ledger_Core.Transactions;
