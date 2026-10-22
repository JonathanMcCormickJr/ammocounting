with Ledger_Core;

--  Minimal assertion helpers; failures are counted and reported at exit.
package Check is

   procedure Eq (Name : String; Got, Want : Ledger_Core.Big);
   procedure Eq (Name : String; Got, Want : Ledger_Core.Int64);
   procedure Eq (Name : String; Got, Want : Ledger_Core.Int32);
   procedure Is_Status (Name : String; Got, Want : Ledger_Core.Status);
   procedure Holds (Name : String; Condition : Boolean);

   function Checks_Run return Natural;
   function Failures return Natural;

end Check;
