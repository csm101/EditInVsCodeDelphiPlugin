# Open in Visual Studio Code (Delphi plugin)

*If you want to have GitHub Copilot AI doing pair-programming with you when you program in Delphi, you need Visual Studio Code and this plugin.*

This Delphi plugin will create a "Tools->Open In Visual Studio Code" menù item in your RAD Studio IDE.

Selecting this option will do just these two simple things:

  1. All modified files opened in your ide will be saved.
  2. The Delphi source file you were editing will be opened in Visual Studio Code, at the exact line you were editing in Rad Studio.
  3. Existing Visual Studio Code instances will be reused (the same source file won't be opened multiple times in different editors)
     
What's so great about using Visual Studio Code as a code editor?
  1. **Copilot with Delphi**: (this is the main reason I wrote this plugin): if you have the Copilot extension installed in Visual Studio Code, it will work perfectly with your Delphi code. This is an incredible game-changer.
  2. Visual Studio Code is simply a far better code editor than the one integrated into the RAD Studio IDE (for example it supports multiple cursors).

## Some cool things you can do with Copilot
 Copilot is an AI specifically trained for programming and it will run inside your visual studio instance: it will understand your code (and your comments!) and it will suggest you code unbelievable code completions.
 It will really feel like you are coding with the help of another programmer working side by side with you.

 Here are some simple screenshots of Copilot suggesting code:

 Here it is completing the `TDaysOfTheWeek` enum (the suggestion is the part in gray: you just have to press "TAB" to accept it)
 
   ![Delphi Programming TDaysOfTheWeek being auto-completed by Copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/62d3115c-4f08-4ad5-a8b5-a6e1238c8b0d)
 
 Same for the `TLanguages` enum:
 
   ![Delphi Programming TLanguages being auto-completed by Copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/96be5322-b890-49fd-831f-dd2620e47e2f)

 Here it suggests a whole function implementation:
 
   ![Whole Delphi Programming function implementation auto-completed by Copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/57f5c114-beaf-4e9d-bff1-608c1bbb1d6a)


You can also chat with the Copilot about a portion of the code you have selected and ask it to explain what it does:

![Copilot explaining Delphi Programming Code](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/d1c2526c-81f5-4420-99f5-cb4d682b14c1)

This is just the tip of the iceberg: you can ask the Copilot to modify your code (with prompts like "use meaningful variable names", "use italian for variable names", "refactor this function by using simpler and smaller local functions", "add comments to this code", "write xml documentation for this class").

## How to use this plugin (Delphi side)

1. Download the source code from this repository
2. Open the package project, build it and install it. 
3. You need to activate this option in Delphi (under Tools->Options->Editor->Language->Delphi->Code Insight).
   (This is necessary to make the LSP Visual Studio Code extension work correctly).
   
  ![How to use this plugin (Delphi side)](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/c254e016-c44a-40ba-afab-a8b5c6246089)

3. (optional) Disable the confirmation requests about reloading a file that is unchanged in the IDE and has been changed externally.
   This will make Delphi reload automatically a file that has been changed on the file system (this applies only if you don't have any pending changes in the editor).
   This will make it more "fluid" to switch back from Visual Studio Code to Delphi.

  ![Disable the confirmation requests](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/c0536311-dc6b-462a-a590-09ab5d715765)

## Install and configure Visual Studio Code  

1. Download and install VSCode from here https://code.visualstudio.com/download
2. Launch VSCode and install the DelphiLSP extension from its marketplace

   ![Launch VSCode and install the DelphiLSP extension from its marketplace](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/d0a6bbf1-8a30-4aa7-bc3a-6c6d1b9a32f7)

   You will also need the copilot extensions:
   
  ![copilot extension](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/aa9473a4-ce94-4130-8007-845112bdf1d1)

## How to enable copilot.
 1. Create a GitHub account (if you already haven't one)
 2. Subscribe for Copilot (look for the menu option "Your Copilot" in the popup menu that opens when you click on your avatar in the top-right corner).
    The first 30 days are a free trial, then it costs 10 dollars/month... I think it is worth every penny.)
 3. Back in Visual Studio Code, sign in with copilot.

    ![In Visual Studio Code, sign in with copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/89ac2bba-b7a9-4be4-a57d-e4f082e20ced)

## Some Handy Visual Studio Code Configuration Tips
### Enable AutoSave in Visual Studio 
 This will make Visual Studio save automatically all the changes to the source file, so whenever you switch back to Delphi you will find in Delphi all the changes you made. If you disabled the reload prompt in Delphi as I suggested, you will get a much better experience.
 *Just remember that Delphi does NOT do an auto-save when you switch back to Visual Studio Code, unless you switch from Delphi to VSC by using the tools->Open In Visual Studio Code menu option*

 This is quite easy, just check this option in the File menu:
 
 ![check this option in the File menu](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/5ee10c81-3a23-4a09-832f-74d6453b5c7d)

### Enable file encoding auto-detection
By default, VSC opens all source files using the UTF8 encoding. It is very likely that you still have some Delphi source files encoded in your local ANSI 8-bit charset.

Search the "Auto Guess Encoding" under VSCode settings, and enable it

![Search the "Auto Guess Encoding" under VSCode settings, and enable it](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/22c8a93a-e14d-4bf1-8031-a08f205d8526)

*you can access the settings tab by pressing "CTRL+," (at least this is the key combination on my Italian keyboard), or by clicking the "gear" icon in the bottomleft  corner of vsc.*

### Enable "ligatures" and install a font that supports them
  This is just something "fancy" but I like it. Maybe you'll like it too: If you use a ligature-supporting font like firacode  you type ">=" but you see "≥": all special character sequences commonly used in programming languages get rendered as the symbol that they should actually represent.

  1. Install this font in Windows: https://github.com/tonsky/FiraCode
  2. look for "Font Family" inside VSCode settings tab and insert "'Fira Code'" as the first font in the comma-separated list (my current setup contains this string, for example, "'Fira Code', Consolas, 'Courier New', monospace")
  3. look for "ligatures" in vscode settings. You will see that you have to select "edit in settings.json" to modify it. Press that "edit in settings.json" link and add "editor.fontLigatures": true, to your configuration file, right before the line about autoGuessEncoding. Mine looks like this:
     
  ![Enable "ligatures" and install a font that supports them](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/710b3e2c-0bc7-4aef-a334-c9a3edc30520)

     
     

    
    
    
    
 




  
     

     
