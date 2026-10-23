package body Ledger_Core.Running with SPARK_Mode is

   use Transactions;

   --  Apply_Transaction on private copies of its inputs: Next, Set and Prev
   --  are distinct objects here, so writing Next can never change what is
   --  still to be read (audit E8).
   procedure Apply_Copy
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
          and then Adds_Exactly (Kind, Set, Prev, Next)
        else Next = Zero_Totals)
   is
      Cells : Wire.Totals := Prev;
   begin
      Next := Zero_Totals;
      if Kind not in Kind_Code then
         Result := Bad_Argument;
         return;
      end if;
      Validate_Set (Set, Result);
      if Result /= Ok then
         return;
      elsif not Valid (Prev) then
         Result := Out_Of_Range;
         return;
      elsif not Balanced (Prev) then
         Result := Unbalanced;
         return;
      end if;

      declare
         Postings : constant Wire.Posting_Array := Postings_Of (Set);
         K        : constant Integer := Integer (Kind);
      begin
         for I in Postings'Range loop
            pragma Loop_Invariant (Valid (Cells));
            pragma Loop_Invariant
              (Total_Debits (Cells) =
                 Total_Debits (Prev) + Side_To (Postings, I - 1, Debit));
            pragma Loop_Invariant
              (Total_Credits (Cells) =
                 Total_Credits (Prev) + Side_To (Postings, I - 1, Credit));
            pragma Loop_Invariant
              (for all KK in 0 .. 3 =>
                 (for all A in 1 .. 5 =>
                    Big (Cells (KK, A).Debits) =
                      Big (Prev (KK, A).Debits)
                      + (if KK = K
                         then Posted_To
                                (Postings, I - 1, Account_Code (A), Debit)
                         else 0)
                    and then Big (Cells (KK, A).Credits) =
                      Big (Prev (KK, A).Credits)
                      + (if KK = K
                         then Posted_To
                                (Postings, I - 1, Account_Code (A), Credit)
                         else 0)));
            declare
               Acct   : constant Integer := Integer (Postings (I).Account);
               Amount : constant Int64 := Postings (I).Amount;
            begin
               if Postings (I).Side = Debit then
                  if Cells (K, Acct).Debits + Amount > Max_Cell then
                     Result := Out_Of_Range;
                     return;
                  end if;
                  Cells (K, Acct).Debits := Cells (K, Acct).Debits + Amount;
               else
                  if Cells (K, Acct).Credits + Amount > Max_Cell then
                     Result := Out_Of_Range;
                     return;
                  end if;
                  Cells (K, Acct).Credits := Cells (K, Acct).Credits + Amount;
               end if;
            end;
         end loop;
      end;

      if not Books_Sound (Cells) then
         Result := Negative_Balance;
      else
         Next   := Cells;
         Result := Ok;
      end if;
   end Apply_Copy;

   procedure Apply_Transaction
     (Kind   : Int32;
      Set    : Wire.Posting_Set;
      Prev   : Wire.Totals;
      Next   : out Wire.Totals;
      Result : out Status)
   is
      --  Read every input before Next is written.
      Local_Set  : constant Wire.Posting_Set := Set;
      Local_Prev : constant Wire.Totals := Prev;
      Cells      : Wire.Totals;
   begin
      Apply_Copy (Kind, Local_Set, Local_Prev, Cells, Result);
      Next := Cells;
   end Apply_Transaction;

   procedure Apply_Typed
     (Kind   : Int32;
      Set    : Wire.Posting_Set;
      Prev   : Wire.Totals;
      Next   : out Wire.Totals;
      Result : out Status)
   is
      Local_Set  : constant Wire.Posting_Set := Set;
      Local_Prev : constant Wire.Totals := Prev;
      Cells      : Wire.Totals := Zero_Totals;
   begin
      if Kind not in Kind_Code then
         Result := Bad_Argument;
      else
         Validate_Set (Local_Set, Result);
         if Result /= Ok then
            null;
         elsif not Has_Shape (Kind, Postings_Of (Local_Set)) then
            Result := Bad_Argument;
         else
            Apply_Copy (Kind, Local_Set, Local_Prev, Cells, Result);
         end if;
      end if;
      Next := Cells;
   end Apply_Typed;

   --  Diff_Totals on private copies of its inputs (see Apply_Copy).
   procedure Diff_Copy
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
        else Diff = Zero_Totals)
   is
   begin
      Diff := Zero_Totals;
      if not Valid (To) or else not Valid (From) then
         Result := Out_Of_Range;
      elsif not Balanced (To) or else not Balanced (From) then
         Result := Unbalanced;
      elsif not Not_Less (To, From) then
         Result := Bad_Order;
      else
         for K in 0 .. 3 loop
            pragma Loop_Invariant
              (for all KK in 0 .. K - 1 =>
                 (for all A in 1 .. 5 =>
                    Diff (KK, A).Debits =
                      To (KK, A).Debits - From (KK, A).Debits
                    and then Diff (KK, A).Credits =
                      To (KK, A).Credits - From (KK, A).Credits));
            for A in 1 .. 5 loop
               pragma Loop_Invariant
                 (for all KK in 0 .. K - 1 =>
                    (for all AA in 1 .. 5 =>
                       Diff (KK, AA).Debits =
                         To (KK, AA).Debits - From (KK, AA).Debits
                       and then Diff (KK, AA).Credits =
                         To (KK, AA).Credits - From (KK, AA).Credits));
               pragma Loop_Invariant
                 (for all AA in 1 .. A - 1 =>
                    Diff (K, AA).Debits =
                      To (K, AA).Debits - From (K, AA).Debits
                    and then Diff (K, AA).Credits =
                      To (K, AA).Credits - From (K, AA).Credits);
               Diff (K, A) :=
                 (Debits  => To (K, A).Debits - From (K, A).Debits,
                  Credits => To (K, A).Credits - From (K, A).Credits);
            end loop;
         end loop;
         Result := Ok;
      end if;
   end Diff_Copy;

   procedure Diff_Totals
     (To     : Wire.Totals;
      From   : Wire.Totals;
      Diff   : out Wire.Totals;
      Result : out Status)
   is
      --  Read both inputs before Diff is written (audit E8).
      Local_To   : constant Wire.Totals := To;
      Local_From : constant Wire.Totals := From;
      Delta_Sums : Wire.Totals;
   begin
      Diff_Copy (Local_To, Local_From, Delta_Sums, Result);
      Diff := Delta_Sums;
   end Diff_Totals;

   procedure Collapse_Kinds
     (Totals    : Wire.Totals;
      Collapsed : out Wire.Account_Totals;
      Result    : out Status)
   is
      Sums : Wire.Account_Totals := (others => (0, 0));
   begin
      if not Valid (Totals) then
         Result := Out_Of_Range;
      else
         for A in 1 .. 5 loop
            pragma Loop_Invariant
              (for all AA in 1 .. A - 1 =>
                 Big (Sums (AA).Debits) =
                   Account_Debits (Totals, Account_Code (AA))
                 and then Big (Sums (AA).Credits) =
                   Account_Credits (Totals, Account_Code (AA))
                 and then Sums (AA).Debits in 0 .. Max_Aggregate
                 and then Sums (AA).Credits in 0 .. Max_Aggregate);
            Sums (A) :=
              (Debits  => Totals (0, A).Debits + Totals (1, A).Debits
                          + Totals (2, A).Debits + Totals (3, A).Debits,
               Credits => Totals (0, A).Credits + Totals (1, A).Credits
                          + Totals (2, A).Credits + Totals (3, A).Credits);
         end loop;
         Result := Ok;
      end if;
      Collapsed := Sums;
   end Collapse_Kinds;

   procedure Audit_Chain (Rows : Wire.Totals_Array; Result : out Status) is
   begin
      Result := Ok;
      for I in Rows'Range loop
         pragma Loop_Invariant (Result = Ok);
         pragma Loop_Invariant
           (for all J in Rows'First .. I - 1 =>
              Valid (Rows (J)) and then Balanced (Rows (J))
              and then Books_Sound (Rows (J))
              and then (if J > Rows'First then
                          Not_Less (Rows (J), Rows (J - 1))));
         if not Valid (Rows (I)) then
            Result := Out_Of_Range;
            return;
         elsif not Balanced (Rows (I)) then
            Result := Unbalanced;
            return;
         elsif not Books_Sound (Rows (I)) then
            Result := Negative_Balance;
            return;
         elsif I > Rows'First and then not Not_Less (Rows (I), Rows (I - 1))
         then
            Result := Bad_Order;
            return;
         end if;
      end loop;
   end Audit_Chain;

end Ledger_Core.Running;
