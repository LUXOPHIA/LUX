program SourceCheck;

// ソースのファイルが、UTF-8 の BOM つきで、行の終わりが CRLF であることを確かめる
//
// ・使い方：SourceCheck <ファイル> [<ファイル> …]   （ファイルの名前には、* と ? を使える）
// ・BOM の無いソースを、コンパイラーは、その機械の地域の文字コードとして読むので、日本語の文字列が化ける。化けても、ビルドは通る。
//   それで、ビルドの前に、ここで止める。
// ・合わないファイルがあれば、名前と理由を出して、終了コード 1 で終わる。

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils;

// ファイルの、合わない所（合っていれば、空）
function Fault( const Path_:String ) :String;
var
   B :TBytes;
   I :Integer;
begin
     B := TFile.ReadAllBytes( Path_ );

     if ( Length( B ) < 3 ) or ( B[ 0 ] <> $EF ) or ( B[ 1 ] <> $BB ) or ( B[ 2 ] <> $BF ) then Exit( 'BOM が無い' );

     for I := 0 to High( B ) do
     begin
          if ( B[ I ] = 10 ) and ( ( I = 0 ) or ( B[ I - 1 ] <> 13 ) ) then Exit( '改行が CRLF でない' );
     end;

     Result := '';
end;

var
   I :Integer;
   D :String;
   P :String;
   F :String;
   S :TArray<String>;

begin
     try
          if ParamCount = 0 then raise EArgumentException.Create( '使い方：SourceCheck <ファイル> [<ファイル> …]' );

          for I := 1 to ParamCount do
          begin
               D := ExtractFilePath( ParamStr( I ) );

               if D = '' then D := '.';

               S := TDirectory.GetFiles( D, ExtractFileName( ParamStr( I ) ) );

               if Length( S ) = 0 then raise EFileNotFoundException.Create( 'ファイルが無い：' + ParamStr( I ) );

               for P in S do
               begin
                    F := Fault( P );

                    if F <> '' then
                    begin
                         Writeln( ErrOutput, F, '：', P );

                         ExitCode := 1;
                    end;
               end;
          end;
     except
          on E:Exception do
          begin
               Writeln( ErrOutput, E.ClassName, '：', E.Message );

               ExitCode := 1;
          end;
     end;
end.
