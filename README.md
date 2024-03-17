# Open in Visual Studio Code (delphi plugin)

*If you want to have GitHub Copilot AI doing pair-programming with you when you program in Delphi, you need Visual Studio Code and this plugin.*

This delphi plugin will create a "Tools->Open In Visual Studio Code" menù item in your RAD Studio IDE.

Selecting this option will do just these two simple things:

  1. All modified files opened in your ide will be saved.
  2. The delphi source file you were editing will be opened in Visual Studio Code, at the exact line you were editing in Rad Studio.
  3. Existing Visual Studio Code instances will be reused (the same source file won't be opened multiple times in different editors)
     
What's so great about using Visual Studio Code as code editor?
  1. **Copilot with Delphi**: (this is the main reason I wrote this plugin for): if you have the copilot extension installed in vscode, it will work perfectly with you delphi code. This is an incredible game changer.
  2. Visual Studio Code is simply a far better code editor than the one integrated in the IDE (for example it supports multiple cursors)

## Some cool things you can do with Copilot
 Copilot is an AI specifically trained for programming and it will run inside your visual studio instance: it will understand your code (and your comments!) and it will suggest you code unbeliveable code completions.
 It will really feel you are coding with the help of another programmer working side by side with you.

 Here are some simple screenshot of copilot suggesting code:

 here it is completing the "daysOfTheWeek" enum (the suggestion is the part in gray: you just have to press "TAB" to accept it)
 
   ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/62d3115c-4f08-4ad5-a8b5-a6e1238c8b0d)
 
 same for the TLanguages enum:
 
   ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/96be5322-b890-49fd-831f-dd2620e47e2f)

 here it is suggesting a whole function implementation:
 
   ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/57f5c114-beaf-4e9d-bff1-608c1bbb1d6a)


You can also chat with copilot about a portion of code you have selected and ask him to explain what does it do:

![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/d1c2526c-81f5-4420-99f5-cb4d682b14c1)

This is just the tip of the iceberg: you can ask copilot to modify your code (with prompts like "use meaningful variable names", "use italian for variable names", "refactor this function by using simpler and smaller local functions", "add comments to this code", "write xml documentation for this class").

## How to use this plugin (delphi side)

1. Download the source code from this repository
2. Open the package project, build it and install it. 
3. You need to activate this option in delphi (under Tools->Options->Editor->Language->Delphi->Code Insight).
   (This is necessary to make the LSP Visual Studio Code extension work correctly).
   
  ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/c254e016-c44a-40ba-afab-a8b5c6246089)

3. (optional) Disable the confirmation requests about reloading a file that is unchanged in the ide and has been changed externally.
   This will make delphi reload automatically a file that has been changed on the file system (this applies only if you don't have any pending changes in the editor).
   This will make more "fluid" to switch back from vscode to delphi.

  ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/c0536311-dc6b-462a-a590-09ab5d715765)

## Install and configure Visual Studio Code  

1. Download and install VSCode from here https://code.visualstudio.com/download
2. Launch VSCode and install the DelphiLSP extension from its maketplace

   ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/d0a6bbf1-8a30-4aa7-bc3a-6c6d1b9a32f7)

   You will also need the copilot extensions:
   
  ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/aa9473a4-ce94-4130-8007-845112bdf1d1)

## How to enable copilot.
 1. Create a GitHub account (if you already haven't one)
 2. Subscribe for copilot (look for the menu option "Your Copilot" in the popup menu that opens when you click on your avatar in the top-right corner).
    The first 30 days are a free trial, then it costs 10 dollars/month... I think it is worth every penny.)
 3. Back in Visual Studio Code, sign in with copilot.

    ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/89ac2bba-b7a9-4be4-a57d-e4f082e20ced)

## Some Handy Visual Studio Code Configuration Tips
### Enable AutoSave in visual studio 
 This will make visual studio save automatically all the changes to the source file, so whenever you switch back to delphi you will find in delphi all the changes you made. If you disabled the reload prompt in delphi as I suggested, you will get a much better experience.
 *Just remember that delphi does NOT do an auto-save when you switch back to visual studio code, unless you switch from delphi to vsc by using the tools->Open In Visual Studio Code menu option*

 This is quite easy, just check this option in the File menu:
 
 ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/5ee10c81-3a23-4a09-832f-74d6453b5c7d)

### Enable file encoding auto detection
By default vsc opens all source files using the UTF8 encoding. It is very likely that you still have some delphi source file still encoded in your local ansi 8 bit charset.

Search the "Auto Guess Encoding" under vscode settings, and enable it

![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/22c8a93a-e14d-4bf1-8031-a08f205d8526)

*you can access the settings tab by pressing "CTRL+," (at least this is the key combination on my Italian keyboard), or by clicking the "gear" icon in the bottomleft  corner of vsc.*

### Enable "ligatures" and install a font that supports them
  This is just something "fancy" but I like it. Maybe you'll like it too: If you use a ligature-supporting font like firacode  you type ">=" but you see "≥": all special character sequences commonly used in programming languages get rendered as the symbol that they should actually represent.

  1. Install this font in windows: https://github.com/tonsky/FiraCode
  2. look for "Font Family" inside vscode settings tab and insert "'Fira Code'" as the first font in the comma separated list (my current setup contains this string, for example "'Fira Code', Consolas, 'Courier New', monospace")
  3. look for "ligatures" in vscode settings. You will see that you have to select "edit in settings.json" to modify it. Press that "edit in settings.json" link and add "editor.fontLigatures": true, to your configuration file, right before the line about autoGuessEncoding. Mine looks like this:
     
  ![image](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/710b3e2c-0bc7-4aef-a334-c9a3edc30520)

     
     

    
    
    
    
 




  
     

     
