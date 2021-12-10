// Bad Apple Atari ST Generator
// by fenarinarsa (Cyril Lambin), 2017
//
// Takes a png sequence and converts it to a pi1/pi3 degas sequence
// Then converts the degas sequence into a delta-packed file for the badapple.tos "player"
// Compiled with Visual Studio Community 2015
//
// Copyright(C) 2017 Cyril Lambin
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.If not, see <https://www.gnu.org/licenses/>.
//
using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Drawing;
using System.IO;
using System.ComponentModel;
using System.Windows.Threading;

namespace BASTGenerator
{

    public partial class MainWindow : Window
    {


        // those are real STE video frequencies (PAL STE) see http://www.atari-forum.com/viewtopic.php?f=16&t=32842&p=335132
        // may be different on STF and NTSC STE. Exact values are important to get a correct audio muxing & replay.
        // audio issues (clicks/duplicate/echoes) on Falcon030 & TT might be related to those values.
        readonly static double pal_fps = 50.05270941;
        readonly static double ntsc_fps = 60.03747642;
        readonly static double vga_fps = 60.15;
        readonly static double monochrome_fps = 71.47532613;

        // uncomment for color
        double fps = vga_fps/2;
        double target_fps = vga_fps/2; // should be >= fps

        int first_pic = 0;
        int last_pic = 4662/2;


        // audio
        int original_samplesize = 2;   // original should always be 16 bits PCM
        int ste_channels = 2;          // 1=mono, 2=stereo (also applies to the input wav file)
        int soundfrq = 50066;       // audio frequency (+/-1Hz depending on the STE main clock). divide by 2 for 25kHz, 4 for 12kHz, etc.
        String soundfile = @"D:\ankha\scratch_50k_16b.wav"; // Original sound file (PCM 16 bit little endian without any tag)

        String runtimesoundfile = @"D:\ankha\ankham_run\ankha_{0:00000}.pcm";

        // Final files 
        String finalvid = @"S:\Emulateurs\Atari ST\HDD_C\DEV\NEW\ankham\asm\audio.dat";
        String finalindex = @"S:\Emulateurs\Atari ST\HDD_C\DEV\NEW\ankham\asm\audio.idx";

        // You can stop here unless you cant to tweak settings in bw_MakeRun.

        public MainWindow()
        {
            InitializeComponent();
        }



        private void bw_ProgressChanged2(object sender, ProgressChangedEventArgs e)
        {

        }


        private void bw_ProgressChanged(object sender, ProgressChangedEventArgs e)
        {
           
        }

        private static Action EmptyDelegate = delegate () { };

        private void MakeRun()
        {

            int trim_start = first_pic;
            int nb_files = last_pic;

            bool write_file = true;
            
            byte[] source = new byte[4];
 
            if (write_file) {
               
                byte[] bufsound = new byte[5000];
                byte[] loadsound = new byte[5000 * original_samplesize];
                using (var sound = new FileStream(soundfile, FileMode.Open, FileAccess.Read)) {
                    int seekstart = 0x2e + ((soundfrq * 2 * trim_start) / ((int)fps * 2)) * 2*2;
                    sound.Seek(seekstart, SeekOrigin.Begin);
                    double framesize = (double)soundfrq / target_fps;
                    double shouldbe = 0;
                    int current = 0;
                    for (int pic = trim_start; pic <= nb_files; pic++) {
                        using (var fs = new FileStream(String.Format(runtimesoundfile, pic), FileMode.Create, FileAccess.Write)) {
                            int toread = ste_channels * (pic==trim_start? (int)framesize-100: (int)framesize);
                            toread = (toread / 2) * 2; // always even
                            shouldbe += ste_channels * (pic == trim_start ? framesize - 100 : framesize);
                            int diff = ((int)shouldbe / 2) *2 - (current + toread);
                            if (diff > 4) toread += diff;
                            else if (diff < -4) toread -= diff;
                            current += toread;
                            Console.WriteLine("audio frame {0}={1} bytes", pic-trim_start, toread);
                            sound.Read(loadsound, 0, toread * original_samplesize);
                            for (int i = 0; i < toread; i++) {
                                if (original_samplesize == 1) {
                                    bufsound[i] = (byte)(bufsound[i] - 0x80);
                                }else {
                                    bufsound[i] = loadsound[original_samplesize * i+1];
                                }
                            }
                            fs.Write(bufsound, 0, toread);
                        }
                    }
                }

                
                int length = 0;
                using (var final = new FileStream(finalvid, FileMode.Create, FileAccess.Write)) {
                    using (var index = new FileStream(finalindex, FileMode.Create, FileAccess.Write)) {
                        for (int pic = trim_start; pic <= nb_files; pic++) {
                            Console.WriteLine("Final file frame {0}", pic-trim_start);
                            int totallength = 0;
                            using (var fs = new FileStream(String.Format(runtimesoundfile, pic), FileMode.Open, FileAccess.Read)) {
                                length = (int)fs.Length;
                                fs.Read(bufsound, 0, length);
                            }

                            source[0] = (byte)((length >> 24) & 0xff);
                            source[1] = (byte)((length >> 16) & 0xff);
                            source[2] = (byte)((length >> 8) & 0xff);
                            source[3] = (byte)(length & 0xff);
                            final.Write(source, 0, 4);
                            final.Write(bufsound, 0, length);
                            totallength = length + 4;

                            source[0] = (byte)((totallength >> 24) & 0xff);
                            source[1] = (byte)((totallength >> 16) & 0xff);
                            source[2] = (byte)((totallength >> 8) & 0xff);
                            source[3] = (byte)(totallength & 0xff);
                            index.Write(source, 2, 2);
                        }
                        // end of index
                        source[0] = (byte)0;
                        source[1] = (byte)0;
                        source[2] = (byte)0;
                        source[3] = (byte)0;
                        index.Write(source, 2, 2);
                    }
                }
            }

        }

        private void btn_runtime_Click(object sender, RoutedEventArgs e)
        {
            MakeRun();
        }
    }

}
