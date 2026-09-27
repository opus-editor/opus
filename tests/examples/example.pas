program LocaleResolver;

{$mode objfpc}

type
  TLocale = record
    Code: string;
    Name: string;
  end;

var
  Locales: array[0..1] of TLocale;
  Wanted: string;
  I: Integer;
  Found: Boolean;

begin
  Locales[0].Code := 'en';
  Locales[0].Name := 'English';
  Locales[1].Code := 'pt-BR';
  Locales[1].Name := 'Português';

  Wanted := 'pt-BR';
  Found := False;

  for I := Low(Locales) to High(Locales) do
  begin
    if Locales[I].Code = Wanted then
    begin
      WriteLn(Locales[I].Name);
      Found := True;
      Break;
    end;
  end;

  if not Found then
    WriteLn('no match');
end.
