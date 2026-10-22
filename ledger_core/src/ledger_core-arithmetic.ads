--  Exact integer rounding helpers. Everything else in the engine is built
--  from these functions, so their bounds are what rule out overflow.
--
--  Each function is an expression function (its body is its definition) and
--  its postcondition restates the result without using the division
--  operator: Q is the floor of N / D exactly when Q * D <= N < (Q + 1) * D.
package Ledger_Core.Arithmetic with SPARK_Mode, Pure is

   subtype Non_Negative is Big range 0 .. 10**18;
   subtype Divisor is Big range 1 .. 10**18;

   --  Q = floor (N / D) over the integers.
   function Is_Floor_Div (N, D, Q : Big) return Boolean is
     (Q >= 0 and then Q * D <= N and then N < (Q + 1) * D)
   with
     Ghost,
     Pre => N in 0 .. 4 * 10**36 and then D in 1 .. 4 * 10**19
            and then Q in 0 .. N / D;

   --  Q = ceil (N / D) over the integers.
   function Is_Ceil_Div (N, D, Q : Big) return Boolean is
     (Q >= 0 and then N <= Q * D and then (Q - 1) * D < N)
   with
     Ghost,
     Pre => N in 0 .. 4 * 10**36 and then D in 1 .. 4 * 10**19
            and then Q in 0 .. (N + D - 1) / D;

   --  round_half_up (A * B / D) = floor ((2 * A * B + D) / (2 * D)), exactly,
   --  with a 128-bit intermediate.
   function Round_Half_Up (A, B : Non_Negative; D : Divisor) return Big is
     ((2 * A * B + D) / (2 * D))
   with
     Post =>
       Is_Floor_Div (2 * A * B + D, 2 * D, Round_Half_Up'Result)
       and then (if B <= D then Round_Half_Up'Result <= A)
       and then (if B = D then Round_Half_Up'Result = A);

   --  ceil (A * B / D), exactly.
   function Ceiling (A, B : Non_Negative; D : Divisor) return Big is
     ((A * B + D - 1) / D)
   with
     Post =>
       Is_Floor_Div (A * B + D - 1, D, Ceiling'Result)
       and then Is_Ceil_Div (A * B, D, Ceiling'Result)
       and then (if B <= D then Ceiling'Result <= A);

   --  Rounding is monotone in each factor: more units never cost less.
   procedure Lemma_Round_Half_Up_Monotone
     (A, B1, B2 : Non_Negative; D : Divisor)
   with
     Ghost,
     Pre  => B1 <= B2,
     Post => Round_Half_Up (A, B1, D) <= Round_Half_Up (A, B2, D);

   --  floor (N / D) for a non-negative numerator: Q is the unique value
   --  with Q * D <= N < (Q + 1) * D.
   function Floor_Div (N : Big; D : Divisor) return Big is (N / D)
   with
     Pre  => N in 0 .. 4 * 10**36,
     Post =>
       Is_Floor_Div (N, D, Floor_Div'Result);

end Ledger_Core.Arithmetic;
