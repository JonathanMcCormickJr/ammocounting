package body Ledger_Core.Arithmetic with SPARK_Mode is

   procedure Lemma_Round_Half_Up_Monotone
     (A, B1, B2 : Non_Negative; D : Divisor)
   is
      Q1 : constant Big := Round_Half_Up (A, B1, D);
      Q2 : constant Big := Round_Half_Up (A, B2, D);
   begin
      pragma Assert (2 * A * B1 <= 2 * A * B2);
      pragma Assert (Q1 * (2 * D) <= 2 * A * B1 + D);
      pragma Assert (2 * A * B2 + D < (Q2 + 1) * (2 * D));
      pragma Assert (Q1 * (2 * D) < (Q2 + 1) * (2 * D));
      pragma Assert (Q1 < Q2 + 1);
   end Lemma_Round_Half_Up_Monotone;

end Ledger_Core.Arithmetic;
