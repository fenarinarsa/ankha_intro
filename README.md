# Ankha Intro

Ankha Intro for Atari Mega STE and ET4000 VGA card


**music:** dDamage  
**graphics** Zone (zone-archive.com)  
**code:** Fenarinarsa  

**Binaries & videos**  
https://demozoo.org/productions/303160/  

**Web**  
https://fenarinarsa.com/ankha-intro  

**Twitter**  
https://twitter.com/fenarinarsa  

**Mastodon**  
https://shelter.moe/@fenarinarsa


# Requirements

Atari Mega STE with at least 2MB RAM  
ET4000 VGA card (tested with NOVA ET4000/AX)  
320x240x256 VGA mode  
ACSI or IDE Hard Drive


# Contents

- asm  
Contains the 68000 source code for the Atari intro.

- BASTGenerator  
Data files generator in C#. To regenerate the audio file.


# Build instructions

You need the following tools:  
- vasm (cross-platform) or Devpac (ST)  
- make (the GNU/Linux tool)  

## vasm

For Windows I offer you my vasm 1.8 binary here (else you need to compile it from source code):  
https://fenarinarsa.com/demos/vasm_mot_1.8.zip  
Official site with source code:  
http://sun.hasenbraten.de/vasm/

And add vasm's path to the environment PATH variable. 

## make

The fastest way to install make on Windows is to install chocolatey:  
https://chocolatey.org/  
Then open a shell as administrator and type:  
`choco install make`

## Build

To build ba.tos, open a shell, go to the "asm" folder and type:  
`make`

You will get a ankha_in.tos.

## Known issues

The intro was only tested on Mega STE 4MB with ET4000/AX with ICS 5301-2 DAC.

There is audio cracks in the party version. I'm working on rewriting the audio engine to make it simpler and more efficient. (currently it's based on the Bad Apple!! player which is overkill).

The NOVA screen saver will fire after a few minutes, because the system Timer C is still active during the demo.  

You can make it compatible with 640x480 by changing the "linewidth" value to 640 (at the start of source code).
