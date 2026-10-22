with Ada.Text_IO;

package body Check is

   use Ledger_Core;

   Run    : Natural := 0;
   Failed : Natural := 0;

   procedure Record_Result
     (Name : String; Passed : Boolean; Got, Want : String) is
   begin
      Run := Run + 1;
      if not Passed then
         Failed := Failed + 1;
         Ada.Text_IO.Put_Line
           ("FAIL " & Name & ": got " & Got & ", want " & Want);
      end if;
   end Record_Result;

   procedure Eq (Name : String; Got, Want : Big) is
   begin
      Record_Result (Name, Got = Want, Big'Image (Got), Big'Image (Want));
   end Eq;

   procedure Eq (Name : String; Got, Want : Int64) is
   begin
      Eq (Name, Big (Got), Big (Want));
   end Eq;

   procedure Eq (Name : String; Got, Want : Int32) is
   begin
      Eq (Name, Big (Got), Big (Want));
   end Eq;

   procedure Is_Status (Name : String; Got, Want : Status) is
   begin
      Record_Result (Name, Got = Want, Status'Image (Got),
                     Status'Image (Want));
   end Is_Status;

   procedure Holds (Name : String; Condition : Boolean) is
   begin
      Record_Result (Name, Condition, "False", "True");
   end Holds;

   function Checks_Run return Natural is (Run);
   function Failures return Natural is (Failed);

end Check;
