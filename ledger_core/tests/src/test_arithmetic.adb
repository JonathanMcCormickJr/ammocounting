with Check;
with Ledger_Core.Arithmetic;

procedure Test_Arithmetic is
   use Ledger_Core.Arithmetic;
begin
   --  Round_Half_Up: floor (A * B / D + 1/2).
   Check.Eq ("rhu 50/4 = 12.5 rounds up", Round_Half_Up (25, 2, 4), 13);
   Check.Eq ("rhu 1/3 rounds down", Round_Half_Up (1, 1, 3), 0);
   Check.Eq ("rhu 2/3 rounds up", Round_Half_Up (2, 1, 3), 1);
   Check.Eq ("rhu exactly half", Round_Half_Up (1, 1, 2), 1);
   Check.Eq ("rhu zero", Round_Half_Up (0, 7, 3), 0);
   Check.Eq ("rhu B = D is A", Round_Half_Up (7, 5, 5), 7);
   Check.Eq ("rhu B < D is at most A", Round_Half_Up (7, 4, 5), 6);
   Check.Eq ("rhu largest operands",
             Round_Half_Up (10**18, 10**18, 10**18), 10**18);

   --  Ceiling: ceil (A * B / D).
   Check.Eq ("ceil exact", Ceiling (25_000, 50, 10_000), 125);
   Check.Eq ("ceil tiny rounds up", Ceiling (1, 1, 10_000), 1);
   Check.Eq ("ceil zero", Ceiling (0, 5, 7), 0);
   Check.Eq ("ceil just over", Ceiling (10_001, 1, 10_000), 2);
   Check.Eq ("ceil B = D is A", Ceiling (9, 3, 3), 9);
   Check.Eq ("ceil largest operands",
             Ceiling (10**18, 10**18, 10**18), 10**18);

   --  Is_Floor_Div / Is_Ceil_Div / Floor_Div (ghost predicates)
   pragma Assert (Is_Floor_Div (7, 2, 3));
   pragma Assert (not Is_Floor_Div (7, 2, 2));
   pragma Assert (Is_Floor_Div (6, 3, 2));
   pragma Assert (Is_Floor_Div (0, 5, 0));
   pragma Assert (Is_Ceil_Div (7, 2, 4));
   pragma Assert (not Is_Ceil_Div (7, 2, 3));
   pragma Assert (Is_Ceil_Div (6, 3, 2));
   pragma Assert (Is_Ceil_Div (0, 5, 0));
   Check.Holds ("floor and ceiling predicates", True);
   Check.Eq ("floor div", Floor_Div (7, 2), 3);
   Check.Eq ("floor div exact", Floor_Div (6, 3), 2);
   Check.Eq ("floor div zero", Floor_Div (0, 5), 0);
   Check.Eq ("floor div large", Floor_Div (10**36, 10**18), 10**18);
   Check.Eq ("floor div by one", Floor_Div (123, 1), 123);

   --  Exact definitions, spot checks of the floor characterisation
   pragma Assert
     (Is_Floor_Div (2 * 25 * 2 + 4, 2 * 4, Round_Half_Up (25, 2, 4)));
   pragma Assert
     (Is_Ceil_Div (25_000 * 50, 10_000, Ceiling (25_000, 50, 10_000)));
   Check.Holds ("exact definitions", True);

   --  (Lemma_Round_Half_Up_Monotone is a ghost lemma: proved, never run.)
   Check.Eq ("monotone: 1 unit of 100", Round_Half_Up (1000, 1, 100), 10);
   Check.Eq ("monotone: 100 units of 100", Round_Half_Up (1000, 100, 100),
             1000);
end Test_Arithmetic;
