package body Ledger_Core.Transactions with SPARK_Mode is

   procedure Validate
     (Postings : Wire.Posting_Array; Result : out Status)
   is
   begin
      if Postings'Length not in 1 .. Max_Postings then
         Result := Bad_Argument;
         return;
      end if;

      for I in Postings'Range loop
         pragma Loop_Invariant
           (for all J in Postings'First .. I - 1 =>
              Well_Formed (Postings (J)));
         if Postings (I).Account not in Account_Code
           or else Postings (I).Side not in Side_Code
           or else Postings (I).Amount < 1
         then
            Result := Bad_Argument;
            return;
         elsif Postings (I).Amount > Max_Amount then
            Result := Out_Of_Range;
            return;
         end if;
      end loop;

      if Total (Postings, Debit) = Total (Postings, Credit) then
         Result := Ok;
      else
         Result := Unbalanced;
      end if;
   end Validate;

   procedure Validate_Set (S : Wire.Posting_Set; Result : out Status) is
   begin
      if S.Count not in 1 .. Max_Postings then
         Result := Bad_Argument;
      else
         Validate (Postings_Of (S), Result);
      end if;
   end Validate_Set;

end Ledger_Core.Transactions;
