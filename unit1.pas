unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Dialogs, StdCtrls, ComCtrls, Spin, ExtCtrls;

const
  ArraySize = 3000;       {maximum number of text chars}
  MaxPat = 9;        {maximum Pattern length}


type

  { TTravestyGenerator }

  TTravestyGenerator = class(TForm)
    btnLoad: TButton;
    btnGenerate: TButton;
    lblSeed: TLabel;
    lblPattern: TLabel;
    lblOutput: TLabel;
    OutputMemo: TMemo;
    OpenDialog1: TOpenDialog;
    PatternLength: TSpinEdit;
    CharacterLength: TSpinEdit;
    RadioProse: TRadioButton;
    RadioVerse: TRadioButton;
    RadioGroup1: TRadioGroup;
    SeedValue: TSpinEdit;
    StatusBar1: TStatusBar;
    procedure btnLoadClick(Sender: TObject);
    procedure btnGenerateClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  TravestyGenerator: TTravestyGenerator;
  BigArray: packed array [1..ArraySize] of char;
  FreqArray, StartSkip: array[' '..'|'] of integer;
  Pattern: packed array [1..MaxPat] of char;
  SkipArray: array [1..ArraySize] of integer;
  OutChars: integer;    {number of characters to be output}
  PatLength: integer;
  f: TextFile;
  OutputText: string;
  fname: ansistring;
  CharCount: integer; {characters so far output}
  Verse, NearEnd: boolean;
  NewChar: char;
  TotalChars: integer; {total chars input, + wraparound}
  Seed: integer;
  i: integer;

implementation

{$R *.lfm}

function Random(var RandInt: integer): real;
begin
  Random := RandInt / 1009;
  RandInt := (31 * RandInt + 11) mod 1009;
end;


procedure ClearFreq;
(*  FreqArray is indexed by 93 probable ASCII characters,            *)
(*  from " " to "|". Its elements are all set to zero.               *)
var
  ch: char;
begin
  for ch := ' ' to '|' do
    FreqArray[ch] := 0;
end; {Procedure ClearFreq}

procedure NullArrays;
(* Fill BigArray and Pattern with nulls *)
var
  j: integer;
begin
  for j := 1 to ArraySize do
    BigArray[j] := CHR(0);
  for j := 1 to MaxPat do
    Pattern[j] := CHR(0);
end; {Procedure NullArrays}

procedure FillArray;
(*    Moves textfile from disk into BigArray, cleaning it            *)
(*    up and reducing any run of blanks to one blank.                *)
(*    Then copies to end of array a string of its opening            *)
(*    characters as long as the Pattern, in effect wrapping          *)
(*    the end to the beginning.                                      *)
var
  Blank: boolean;
  ch: char;
  j: integer;

  procedure Cleanup;
  (* Clears Carriage Returns, Linefeeds, and Tabs out of            *)
  (* input stream. All are changed to blanks.                       *)
  begin
    if ((ch = CHR(13))     {CR} or (ch = CHR(10))   {LF} or (ch = CHR(9)))
    {TAB} then
      ch := ' ';
  end;

begin {Procedure FillArray}
  j := 1;
  Blank := False;
  while (not EOF(f)) and (j <= (ArraySize - MaxPat)) do
  begin {While Not EOF}
    Read(f, ch);
    Cleanup;
    BigArray[j] := ch;                    {Place character in BigArray}
    if ch = '' then
      Blank := True;
    j := j + 1;
    while (Blank and (not EOF(f)) and (j <= (ArraySize - MaxPat))) do
    begin {While Blank}                    {When a blank has just been}
      Read(f, ch);                            {printed, Blank is true,}
      Cleanup;                      {so succeeding blanks are skipped,}
      if ch <> '' then                            {thus stopping runs.}
      begin {If}
        Blank := False;
        BigArray[j] := ch;                 {To BigArray if not a Blank}
        j := j + 1;
      end; {If}
    end; {While Blank}
  end; {While Not EOF}
  TotalChars := j - 1;
  if BigArray[TotalChars] <> '' then
  begin   {If no Blank at end of text, append one}
    TotalChars := TotalChars + 1;
    BigArray[TotalChars] := ' ';
  end;
  {Copy front of array to back to simulate wraparound.}
  for j := 1 to PatLength do
    BigArray[TotalChars + j] := BigArray[j];
  TotalChars := TotalChars + PatLength;
  TravestyGenerator.StatusBar1.SimpleText :=
    'Characters read, plus wraparound = ' + IntToStr(TotalChars);
end; {Procedure FillArray}

procedure FirstPattern;
(* User selects "order" of operation, an integer, n, in the          *)
(* range 1 .. 9. The input text will henceforth be scanned           *)
(* in n-sized chunks. The first n-1 characters of the input          *)
(* file are placed in the "Pattern" Array. The Pattern is            *)
(* written at the head of output.                                    *)
var
  j: integer;
begin
  for j := 1 to PatLength do           {Put opening chars into Pattern}
    Pattern[j] := BigArray[j];
  CharCount := PatLength;
  NearEnd := False;
  if Verse then
    OutputText := OutputText + ' ';
  {Align first line}
  for j := 1 to PatLength do
    OutputText := OutputText + Pattern[j];
end; {Procedure FirstPattern}

procedure InitSkip;
(*   The i-th entry of SkipArray contains the smallest index         *)
(*   j > i such that BigArray[j] = BigArray[i]. Thus SkipArray       *)
(*   links together all identical characters in BigArray.            *)
(*   StartSkip contains the index of the first occurrence of         *)
(*   each character. These two arrays are used to skip the           *)
(*   matching routine through the text, stopping only at             *)
(*   locations whose character matches the first character           *)
(*   in Pattern.                                                     *)
var
  ch: char;
  j: integer;
begin
  for ch := ' ' to '|' do
    StartSkip[ch] := TotalChars + 1;
  for j := TotalChars downto 1 do
  begin
    ch := BigArray[j];
    SkipArray[j] := StartSkip[ch];
    StartSkip[ch] := j;
  end;
end; {Procedure InitSkip}

procedure Match;
(*   Checks BigArray for strings that match Pattern; for each        *)
(*   match found, notes following character and increments its       *)
(*   count in FreqArray. Position for first trial comes from         *)
(*   StartSkip; thereafter positions are taken from SkipArray.       *)
(*   Thus no sequence is checked unless its first character is       *)
(*   already known to match first character of Pattern.              *)
var
  i: integer;     {one location before start of the match in BigArray}
  j: integer; {index into Pattern}
  Found: boolean;      {true if there is a match from i+1 to i+j - 1 }
  ch1: char;       {the first character in Pattern; used for skipping}
  NxtCh: char;
begin {Procedure Match}
  ch1 := Pattern[1];
  i := StartSkip[ch1] - 1;         {is is 1 to left of the Match start}
  while (i <= TotalChars - PatLength - 1) do
  begin {While}
    j := 1;
    Found := True;
    while (Found and (j <= PatLength)) do
      if BigArray[i + j] <> Pattern[j] then
        Found := False   {Go thru Pattern til Match fails}
      else
        j := j + 1;
    if Found then
    begin            {Note next char and increment FreqArray}
      NxtCh := BigArray[i + PatLength + 1];
      FreqArray[NxtCh] := FreqArray[NxtCh] + 1;
    end;
    i := SkipArray[i + 1] - 1;  {Skip to next matching position}
  end; {While}
end; {Procedure Match}

procedure WriteCharacter;
(*   The next character is written. It is chosen at Random           *)
(*   from characters accumulated in FreqArray during last            *)
(*   scan of input. Output lines will average 50 character           *)
(*   in length. If "Verse" option has been selected, a new           *)
(*   line will commence after any word that ends with "|" in         *)
(*   input file. Thereafter lines will be indented until             *)
(*   the 50-character average has been made up.                      *)
var
  Counter, Total, Toss: integer;
  ch: char;
begin
  Total := 0;
  for ch := ' ' to '|' do
    Total := Total + FreqArray[ch]; {Sum counts in FreqArray}
  Toss := TRUNC(Total * Random(Seed)) + 1;
  Counter := 31;
  repeat
    Counter := Counter + 1;                         {We begin with ' '}
    Toss := Toss - FreqArray[CHR(Counter)]
  until Toss <= 0;                                   {Char chosen by}
  NewChar := CHR(Counter);                    {successive subtractions}
  if NewChar <> '|' then
    OutputText := OutputText + NewChar;
  CharCount := CharCount + 1;
  if CharCount mod 50 = 0 then
    NearEnd := True;
  if ((Verse) and (NewChar = '|')) then
    OutputText := OutputText + sLineBreak;
  if ((NearEnd) and (NewChar = ' ')) then
  begin {If NearEnd}
    OutputText := OutputText + sLineBreak;
    if Verse then
      OutputText := OutputText + '     ';
    NearEnd := False;
  end; {If NearEnd}
end; {Procedure Write Character}

procedure NewPattern;
(*   This removes the first character of the Pattern and             *)
(*   appends the character just printed. FreqArray is                *)
(*   zeroed in preparation for a new scan.                           *)
var
  j: integer;
begin
  for j := 1 to PatLength - 1 do
    Pattern[j] := Pattern[j + 1];             {Move all chars leftward}
  Pattern[PatLength] := NewChar;                       {Append NewChar}
  ClearFreq;
end; {Procedure NewPattern}

{ TTravestyGenerator }

procedure TTravestyGenerator.btnLoadClick(Sender: TObject);
begin
  OpenDialog1.Execute;
  fname := OpenDialog1.FileName;
  AssignFile(f, fname);
  reset(f);
  TravestyGenerator.StatusBar1.SimpleText := fname;
  btnGenerate.Enabled := True;
end;

procedure TTravestyGenerator.btnGenerateClick(Sender: TObject);
begin
  TravestyGenerator.OutputMemo.Clear;
  Seed := SeedValue.Value;
  OutChars := CharacterLength.Value;
  PatLength := PatternLength.Value;
  if (RadioProse.Checked = True) then
    Verse := False
  else
    Verse := True;
  OutputText := '';
  ClearFreq;
  NullArrays;
  FillArray;
  FirstPattern;
  InitSkip;
  repeat
    Match;
    WriteCharacter;
    NewPattern
  until CharCount >= OutChars;
  TravestyGenerator.OutputMemo.Text :=
    TravestyGenerator.OutputMemo.Text + sLineBreak + OutputText;
end;

procedure TTravestyGenerator.FormCreate(Sender: TObject);
begin
  Randomize;
  btnGenerate.Enabled := False;
  TravestyGenerator.OutputMemo.Text :=
    '         Travesty' + sLineBreak + '         --------' + sLineBreak +
    '   The Dissociated Press' + sLineBreak + '      parody generator' +
    sLineBreak + sLineBreak + 'This program takes in a source text file and scrambles it.' +
    sLineBreak +
    'The process for doing this produces similar results to a Markov chain algorithm, although it works differently.'
    +
    sLineBreak +
    'The algorithm starts by printing any N consecutive words (or letters) in the text. Then at every step it searches for any random occurrence in the original text of the last N words (or letters) already printed and then prints the next word or letter.' + sLineBreak + sLineBreak + 'Notes for use:' + sLineBreak + 'Pattern length' + sLineBreak + '2 - Produces gibberish' + sLineBreak + '4 - is understandable' + sLineBreak + '8 - is most like the input text';
end;


end.
