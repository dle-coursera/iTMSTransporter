:: For more information on the shell builtins used in this script, open a DOS
:: command prompt, and type "help <builtinName>":
:: - cd
:: - cmd
:: - del
:: - echo
:: - endlocal
:: - exit
:: - findstr
:: - for
:: - goto
:: - if
:: - pause
:: - prompt
:: - set
:: - setlocal
:: - shift
:: - title
::
:: Some interesting Windows scripting notes that will be of help in
:: understanding this launch script:
:: - If you invoke echo with a variable that evaluates to the empty string,
::   echo will print a status message, not an empty string itself.
::   "help echo" for more info.
:: - Since the equals sign is a metacharacter used in string substitutions,
::   it's very difficult to replace it with something else.  Also, when
::   doing text processing, particularly with invocations of the set builtin,
::   equals signs are interpreted as spaces; this is inexplicable but very
::   much the case.  We hedge against this below by replacing the equals sign
::   character in arguments (e.g. "-Dx=y") with a unique token so that it may
::   be restored later.
:: - Although Windows scripting now allows you to perform blocks of operations
::   within a conditional or loop, the command processor isn't intelligent
::   about handling instances of the block metacharacters (the parenthesis
::   characters, in this case) as values in dereferenced variables.  This
::   causes problems if you want to, say, pass an ASCII property list
::   representation of a string as a value for, say, NSProjectSearchPath.
::   As with the equals sign, we replace these characters with unique tokens
::   so that the characters may be restored later.  This token replacement
::   is much simpler for these characters than it is for the equals sign
::   character, though.
:: - When you echo the character sequence "%%", it collapses to a single "%".
:: - We need to create temporary, helper scripts, and sometimes these scripts
::   echo text to another file.  This is a problem when generating the helper
::   script on the fly, because the act of generating the script itself
::   involves echo text to a file; you run into the difficulty of having
::   stdout redirected twice on the same line, which would confuse the command
::   interpreter.  We rely on an old DOS trick of abusing the prompt builtin to
::   hack together sketchy character sequences in a subshell and harvest the
::   resulting prompt and echo *that* to the script.  All uses of the prompt
::   builtin address this problem alone.  You'll notice that the script line
::   up to the "prompt" keyword is identical in every instance; for more info
::   check "help cmd", "help for" and "help prompt".  This is a trick
::   that should be documented in various Windows scripting sites on the WWW.
:: - Windows scripting doesn't treat single quotes specially.  Don't use single
::   quotes to quote arguments (e.g. arguments that contain spaces) to pass to
::   this launch script.
:: - Setting a variable like "set BLAH=" is the same semantic for undefining a
::   variable.  Instead of checks for whether the value of the variable is
::   empty, all we have to do is check whether the variable is defined.
::   Unfortunately, this sort of check doesn't work for automatic variables
::   such as those used by for loops (e.g. "%%a", etc).
:: - If you echo a variable where the last character of the value is a number,
::   and you redirect this echo to a file, the command processor will try to
::   interpret the number as a file descriptor (e.g. "1>" means stdout, "2>"
::   means stderr), regardless of the number, and will effectively eat the
::   number.  This causes big problems if you pass arguments to the script
::   like "-DNSDebugLevel=1".  You need to ensure that a space always follows
::   the echo invocation before the redirection.

:: Turn off echo.
@echo off
::@echo on

for /F "tokens=*" %%a in ('cd') do set CDDIR=%%~fa
%~d0
cd "%~p0"

:: Use the setlocal builtin to test whether we're running on a supported version
:: of Windows.  If not, exit.
set BADWINVR=no
setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
if errorlevel 1 set BADWINVR=yes
if not "%BADWINVR%"=="no" (
   echo This version of WebObjects is not supported on this version of Windows.  Terminating. 1>&2
   set BADWINVER=
   if not "%NOPAUSE%"=="yes" pause
   exit /B 1
)
endlocal
set BADWINVER=

:: Unfortunately, the scripting environment isn't very intelligent about what
:: changes it considers "local".  If setlocal is active, changes made in for
:: loops have no cumulative effect (the changes are local to that iteration of
:: the for loop).  So we can't use setlocal for its main behavior.  We will
:: also unset any variables that might have been left laying around in a
:: previous launch in this same shell and that aren't explicitly cleared or
:: initialized before their first use.
set ARGLIST=
set JAVAARGS=
set JVARGS=
set JXARGS=
set NONXARGS=
set TEMPARGS=
set THEARGS=

:: Grab the path to the current working directory, before we change directories
:: into the application wrapper.
:: We need this for the benefit of applications like JavaConverter.
for /F "tokens=*" %%a in ('cd') do set CURRDIR=%%~fsa
set CURRDIR=%CURRDIR:\=/%

:: Change the titlebar for this window.
set APPNAME=%~n0
title %APPNAME%

:: Argument for the Windows launch script only:
::   -WONoPause YES: Do not execute pauses for user input during startup
set NOPAUSE=no
echo %* | findstr /I /R /C:"WONoPause  *true" /C:"WONoPause  *YES" /C:"WONoPause=true" /C:"WONoPause=YES" > nul 2> nul
if not errorlevel 1 set NOPAUSE=yes

:: echo Configuring launch environment for %~n0 ...

:: Keep track of the failure state.  Try to log as many error conditions
:: at once as possible.
set FAILURE=no

if not defined TEMP echo TEMP environment variable is not defined -- define it and relaunch! 1>&2
if not defined TEMP set FAILURE=yes

:: Figure out where the launch configuration activity needs to occur.
:: Scratch files will be created there.
:: We prefer to use the short version of TEMP (SDRNM).
for /F "tokens=*" %%a in ("%TEMP%") do set SDRNM=%%~fsa

:: These are all of the scratch files used to configure and launch the app.
:: NOTE: There had better be no spaces in any of these directories
::       or filenames, hence the use of SDRNM.
set APPID=%APPNAME%-%RANDOM%
set ARGCMD1FL=%SDRNM%\%APPID%-1.CMD
set ARGCMD2FL=%SDRNM%\%APPID%-2.CMD
set ARGCMD3FL=%SDRNM%\%APPID%-3.CMD
set ARG1FL=%SDRNM%\%APPID%-4.TXT
set ARG2FL=%SDRNM%\%APPID%-5.TXT
set ARG3FL=%SDRNM%\%APPID%-6.TXT
set ARG4FL=%SDRNM%\%APPID%-7.TXT
set ARG5FL=%SDRNM%\%APPID%-8.TXT
set ARG6FL=%SDRNM%\%APPID%-9.TXT
set JARGFL=%SDRNM%\%APPID%-10.TXT
set JXARGFL=%SDRNM%\%APPID%-11.TXT
set JVERFL=%SDRNM%\%APPID%-12.TXT

:: These environment variables vary for each system and/or user.
:: The script variables set as a result will be used to create real
:: paths out of the abstractions in the classpath file.
:: NOTE: There might be a relevant complaint from above about the
::       lack of the TEMP environment variable.

:: if not defined NEXT_ROOT echo NEXT_ROOT is not defined -- WORootDirectory and WOLocalRootDirectory set to empty string! 1>&2
if not defined NEXT_ROOT goto ENDROOTDEF

for /F "tokens=*" %%a in ("%NEXT_ROOT%") do set WOROOT=%%~fa
set WOROOT=%WOROOT:\=/%

for /F "tokens=*" %%a in ("%NEXT_ROOT%\Local") do set LOCALROOT=%%~fa
set LOCALROOT=%LOCALROOT:\=/%

:ENDROOTDEF

:: Quit if there were problems getting crucial environment variables.
:: NOTE: Don't remove the scratch directory if it's somehow being reused.
if not "%FAILURE%"=="no" if not "%NOPAUSE%"=="yes" pause
if not "%FAILURE%"=="no" exit /B 1

:: These are the arguments passed to the script.
set THEARGS=%* -callerPWD "%CDDIR%"

:: If there are no command-line args, skip argument processing.
if not defined THEARGS goto ENDHANDLEARGS

:: Several characters that might be in the argument are script metacharacters.
:: If so, replace them with unique tokens for later reversion.
if defined THEARGS set THEARGS=%THEARGS:(=LeftParenthesisToken%
if defined THEARGS set THEARGS=%THEARGS:)=RightParenthesisToken%
if defined THEARGS set THEARGS=%THEARGS:!=ExclamationToken%
if defined THEARGS set THEARGS=%THEARGS:;=SemicolonToken%

:: Determine which launch args we want to pass directly to the JVM (beginning
:: with -D and containing an = sign) and build a string with just those args.
:: This requires two steps:
:: First, we need to substitute a special delimiter string for the '='
:: character because, while we can use %1, %2, ... to handle spaces in our
:: arguments, those conventions handle the '=' sign in a very strange way.
:: NOTE: Besides the complication of handling spaces in argument values,
::       some old-style arguments start with "-D" (e.g. "-D2WSomeOption YES").
echo %THEARGS% > %ARG1FL%

echo @echo off> %ARGCMD1FL%
::echo @echo on> %ARGCMD1FL%
echo set ARGLIST=>> %ARGCMD1FL%
echo :SUBSTEQ>> %ARGCMD1FL%
echo for /F "tokens=1* delims==" %%%%i in (%ARG1FL%) do (>> %ARGCMD1FL%
echo     if defined ARGLIST (>> %ARGCMD1FL%
echo         set ARGLIST=!ARGLIST!EqualsDelimiterToken>> %ARGCMD1FL%
echo     )>> %ARGCMD1FL%
echo     set ARGLIST=!ARGLIST!%%%%i>> %ARGCMD1FL%
echo     if not '%%%%j'=='' (>> %ARGCMD1FL%
cmd /A /X /C for /L %%v in (1,1,2) do prompt echo %%%%j $g %ARG1FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD1FL%
echo         goto :SUBSTEQ>> %ARGCMD1FL%
echo     )>> %ARGCMD1FL%
echo )>> %ARGCMD1FL%
cmd /A /X /C for /L %%v in (1,1,2) do prompt if defined ARGLIST echo !ARGLIST! $g %ARG2FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD1FL%

cmd /V:ON /A /X /C %ARGCMD1FL%

set TEMPARGS=
:: NOTE: TEMPARGS now contains all of the command line args with "=" replaced
::       by "EqualsDelimiterToken".
if exist %ARG2FL% for /F "tokens=*" %%a in (%ARG2FL%) do set TEMPARGS=%%a

:: Second, we break the args each on one line for ease of processing,
:: taking advantage of one of the few shell-like behaviors of batch
:: scripting -- arg processing.
:: Then, we separate -X (JVM-specific) args from all others and write them to
:: two different files.
echo @echo off> %ARGCMD2FL%
::echo @echo on> %ARGCMD2FL%
echo :PARSARGS>> %ARGCMD2FL%
:: The following was added for a special case of a parameter with a value of "off" (or "on"), since issuing "echo off"
:: has the effect of disabling echoing rather than actually echoing the string "off".
echo if '%%1'=='off' (>> %ARGCMD2FL%
cmd /A /C for /L %%v in (1,1,2) do prompt echo "off" $g$g %ARG3FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD2FL%
echo     shift>> %ARGCMD2FL%
echo     goto :PARSARGS>> %ARGCMD2FL%
echo )>> %ARGCMD2FL%
echo if '%%1'=='on' (>> %ARGCMD2FL%
cmd /A /C for /L %%v in (1,1,2) do prompt echo "on" $g$g %ARG3FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD2FL%
echo     shift>> %ARGCMD2FL%
echo     goto :PARSARGS>> %ARGCMD2FL%
echo )>> %ARGCMD2FL%
echo if not '%%1'=='' (>> %ARGCMD2FL%
cmd /A /C for /L %%v in (1,1,2) do prompt echo %%1 $g$g %ARG3FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD2FL%
echo     shift>> %ARGCMD2FL%
echo     goto :PARSARGS>> %ARGCMD2FL%
echo )>> %ARGCMD2FL%
echo set JXARGS=>> %ARGCMD2FL%
echo if exist %ARG3FL% for /F "tokens=*" %%%%a in ('findstr /R "\-X.*" %ARG3FL%') do (>> %ARGCMD2FL%
echo    if not '%%%%a'=='' (>> %ARGCMD2FL%
echo       set JXARGS=!JXARGS!%%%%a>> %ARGCMD2FL%
echo    )>> %ARGCMD2FL%
echo )>> %ARGCMD2FL%
cmd /A /C for /L %%v in (1,1,2) do prompt if defined JXARGS echo !JXARGS! $g$g %JXARGFL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD2FL%
echo set TEMPARGS=>> %ARGCMD2FL%
echo if exist %ARG3FL% for /F "tokens=*" %%%%a in ('findstr /V /R "\-X.*" %ARG3FL%') do (>> %ARGCMD2FL%
echo    if not '%%%%a'=='' (>> %ARGCMD2FL%
echo       set TEMPARGS=!TEMPARGS!%%%%a>> %ARGCMD2FL%
echo    )>> %ARGCMD2FL%
echo )>> %ARGCMD2FL%
cmd /A /C for /L %%v in (1,1,2) do prompt if defined TEMPARGS echo !TEMPARGS! $g$g %ARG4FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD2FL%

cmd /V:ON /A /X /C %ARGCMD2FL% %TEMPARGS%

:: Third, we read back in the separated args.
set TEMPARGS=
:: NOTE: TEMPARGS now contains all of the command line args with "=" replaced
::       by "EqualsDelimiterToken", sans any arguments that start with "-X".
::       "-X" arguments end up in JXARGS.
if exist %ARG4FL% for /F "tokens=*" %%a in (%ARG4FL%) do set TEMPARGS=%%a
set JXARGS=
if exist %JXARGFL% for /F "tokens=*" %%a in (%JXARGFL%) do set JXARGS=%%a
set JXARGS=-Xrs %JXARGS%

:: Fourth, we need to examine each argument to see if it meets our format
:: requirement (-D*=*) and if so then include it in our Java arguments string,
:: and replace the '=' delimiter string at the end.
:: Lastly, read back in all non-"-X" args and repopulate THEARGS.
echo @echo off> %ARGCMD3FL%
::echo @echo on> %ARGCMD3FL%
echo :PARSARGS>> %ARGCMD3FL%
echo if not '%%1'=='' (>> %ARGCMD3FL%
cmd /A /C for /L %%v in (1,1,2) do prompt echo %%1 $g$g %ARG5FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD3FL%
echo     shift>> %ARGCMD3FL%
echo     goto :PARSARGS>> %ARGCMD3FL%
echo )>> %ARGCMD3FL%
echo set JVARGS=>> %ARGCMD3FL%
echo for /F "tokens=*" %%%%a in ('findstr /R "\-D.*EqualsDelimiterToken.*" %ARG5FL%') do if not '%%%%a'=='' set JVARGS=!JVARGS!%%%%a>> %ARGCMD3FL% 
cmd /A /X /C for /L %%v in (1,1,2) do prompt if defined JVARGS echo %%JVARGS:EqualsDelimiterToken==%% $g %JARGFL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD3FL%
echo set NONXARGS=>> %ARGCMD3FL%
echo for /F "tokens=*" %%%%a in (%ARG5FL%) do if not '%%%%a'=='' set NONXARGS=!NONXARGS!%%%%a>> %ARGCMD3FL%
cmd /A /C for /L %%v in (1,1,2) do prompt if defined NONXARGS echo %%NONXARGS:EqualsDelimiterToken==%% $g$g %ARG6FL% $_| findstr /V "$g" | findstr /V /R "^$">> %ARGCMD3FL%

cmd /V:ON /A /X /C %ARGCMD3FL% %TEMPARGS%

:: Reset THEARGS here, because we want to prune all the -X args from the args
:: given to the woapp, not just copy them to the front of the arg list.
if exist %ARG6FL% for /F "tokens=*" %%a in (%ARG6FL%) do set THEARGS=%%a

set JAVAARGS=
if exist %JARGFL% for /F "tokens=*" %%a in (%JARGFL%) do set JAVAARGS=%%a
set JAVAARGS=%JXARGS% %JAVAARGS%

:: Restore script metacharacters in the arguments (see above).
if defined THEARGS set THEARGS=%THEARGS:LeftParenthesisToken=(%
if defined THEARGS set THEARGS=%THEARGS:RightParenthesisToken=)%
if defined THEARGS set THEARGS=%THEARGS:ExclamationToken=!%
if defined THEARGS set THEARGS=%THEARGS:SemicolonToken=;%
if defined JAVAARGS set JAVAARGS=%JAVAARGS:LeftParenthesisToken=(%
if defined JAVAARGS set JAVAARGS=%JAVAARGS:RightParenthesisToken=)%
if defined JAVAARGS set JAVAARGS=%JAVAARGS:ExclamationToken=!%
if defined JAVAARGS set JAVAARGS=%JAVAARGS:SemicolonToken=;%

:: Delete any scratch files previously used for argument processing.
del /F /Q %ARG1FL% %ARG2FL% %ARG3FL% %ARG4FL% %ARG5FL% %ARG6FL% %ARGCMD1FL% %ARGCMD2FL% %ARGCMD3FL% %JARGFL% %JXARGFL% > nul 2> nul

:ENDHANDLEARGS

set JVM=java
set JVMOPTS=-Xmx1024m -Xms1024m -Djava.awt.headless=true -Dsun.net.http.retryPost=false
set APPLICATION_CLASS=com.apple.transporter.Application

:: Even in the case of no command-line args, we need to pass certain arguments
:: used by the WebObjects runtime.
set JAVAARGS=%JAVAARGS% -DWORootDirectory="%WOROOT%" -DWOLocalRootDirectory="%LOCALROOT%" -DWOUserDirectory="%CURRDIR%"
if not defined CLASSPATH goto ENDENVCPDEF
set JAVAARGS=%JAVAARGS% -DWOEnvClassPath="%CLASSPATH:\=/%"
:ENDENVCPDEF
set JAVAARGS=%JAVAARGS% -DWOApplicationClass=%APPLICATION_CLASS% -DWOPlatform=Windows

:: Set up Aspera library path location.
set JAVAARGS=%JAVAARGS% -Djava.library.path="%USERPROFILE%\.itmstransporter\aspera\bin\windows-32"

:: Determine whether the debugger or the JVM should be invoked.
set JAVAEXE=%JVM%

:: We need to make sure they are running the correct version of java
:: get the version
set JAVAVEREXE=%JAVAEXE% -version
:: echo JAVAVEREXE = %JAVAVEREXE%
cmd /A /Q /C %JAVAVEREXE%> nul 2> %JVERFL%

:: see if the version is 1.7
findstr /R "1.7." %JVERFL% >nul 2> nul
set JAVAVERRETVAL=%ERRORLEVEL%

:: if they aren't using 1.7, see if they are using 1.8
if %JAVAVERRETVAL% NEQ 0 findstr /R "1.8." %JVERFL% >nul 2> nul
if %JAVAVERRETVAL% NEQ 0 set JAVAVERRETVAL=%ERRORLEVEL%

:: if they aren't using 1.7 or 1.8, see if they are using 1.9
if %JAVAVERRETVAL% NEQ 0 findstr /R "1.9." %JVERFL% >nul 2> nul
if %JAVAVERRETVAL% NEQ 0 set JAVAVERRETVAL=%ERRORLEVEL%

:: if they aren't using a supported version of Java, display an error and exit
if %JAVAVERRETVAL% NEQ 0 echo Java 1.7, Java 1.8, or Java 1.9 is required. Please upgrade. The current default java version is ...
if %JAVAVERRETVAL% NEQ 0 type %JVERFL%
if %JAVAVERRETVAL% NEQ 0 exit /B % JAVAVERRETVAL%

:: Delete the last scratch file previously used for java version checking.
del /F /Q %JVERFL% > nul 2> nul

:: Launch the application.
:: echo Launching %~n0.
call %JAVAEXE% %JVMOPTS% %JAVAARGS% -classpath ./lib/itmstransporter-launcher.jar %APPLICATION_CLASS% %THEARGS%

:: Capture the exit code returned by the JVM (important in the event
:: of an error).
set RETVAL=%ERRORLEVEL%
cd "%CDDIR%"

:: Return the exit code provided by the terminated Java process.
if not "%NOPAUSE%"=="yes" pause
exit /B %RETVAL%
