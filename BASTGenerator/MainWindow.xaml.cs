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
        // What is this?
        // It's the C# program that generates data file for the badapple.tos Atari ST "player"
        //
        // What do I need?
        // Visual Studio Community 2015, vasm m68k and the assets available at https://fenarinarsa.com/badapple/fenarinarsa_badapple_source.zip
        //
        // How does it work?
        //
        // It works in 4 steps:
        //
        // Step 1
        // Takes a PNG sequence and converts it into a PI1 (low-res) or PI3 (high-res monochrome) sequence.
        // The PNG images MUST BE RESIZED TO THE FINAL RESOLUTION
        // That is: 320x200 for low-res and 640x400 for high-res
        // The conversion will take only the green channel to make the conversion and take the nearest greyscale available.
        // PI1 will always be greyscale, number of bitplanes (1/2/3/4) defined by 'target_nb_bitplanes'.
        //   => each bitplane setting will output in a different directory
        // PI3 will always be black & white.
        //
        // Step 2
        // Takes the PI1/PI3 sequence and make an analysis of the differences between frames.
        // It then generates a ".run" file, one per image, containing m68k code and/or blitter data.
        // Parameters of the analysis can be tuned in bw_MakeRun. The most interesting setting is opt_blitter to enable or disable blitter rendering.
        //
        // Step 3
        // Takes an audio file and split it into audio frames (.pcm), one per image.
        // The audio file must be a 16-bits PCM wav with the correct STE final frequency, for instance 50066Hz stereo
        // and please do NOT set any tag in this file (no author composer etc.).
        //
        // Step 4
        // Muxes the .run and .pcm files and generates a ba.dat file (data) and ba.idx file (index)
        //
        // On the UI
        // The first button runs pass 1
        // The second button runs pass 2+3+4 unless in source 'audio_mux_only' is set to "true", in this case it runs pass 3+4 only.
        //
        // Note that the settings in badapple.tos must match the ones in ba.dat, for instance set 'monochrome' to 1 when it's a high-res ba.dat file.
        //
        // Also this generator converts framerate.
        // fps is the framerate the original sequence should be played at (bad apple is 30 fps)
        // target_fps is the framerate it will be played on ST.
        // => lowres: define fps=ntsc_fps/2 so that the fps of the sequence will be a little faster than 30fps but will match the STE clock.
        // => highres: define fps=30 and target_fps=monochrome_fps, so the resulting sequence will have a lot more frames but a lot will contain only audio ("unchanged frames")
        // This is really important to get a good sync between audio and video
        //
        // == ba.dat file format
        // contains all frames sequentially
        // everything is big-endian of course, this is the right order :)
        // w=16 bits
        // -- 1 frame:
        // 1w size of audio frame in bytes, should always be even
        // ?w audio frame
        // 1w size of render code in bytes. if 0x0000: no render, this is an "unchanged frame". Keep the previous render displayed (no buffer swap)
        // ?w code to execute, register a6 must contain the video buffer address, always ends with 0x4e75 (rts)
        // 1w number of blitter operations. -1 if no blitter operation
        // --- blitter operation
        // 1w number of bitplanes (1/2/4)
        // 1w offset from start of screen in bytes (signed, so max 32767)
        // 1w vertical size of operation (number of lines)
        // 1w HOP+OP   (0x0203 copy / 0x0100 and 0x010F blitter fill)
        // ?w graphic data to copy if HOP+OP==0x0203, length of data in bytes = number of bitplanes * lines * 2
        //
        // == ba.idx file format
        // contains the size of each frame. 1w (unsigned) by frame.
        // ends with 0x0000
        //

        BackgroundWorker bw;

        // those are real STE video frequencies (PAL STE) see http://www.atari-forum.com/viewtopic.php?f=16&t=32842&p=335132
        // may be different on STF and NTSC STE. Exact values are important to get a correct audio muxing & replay.
        // audio issues (clicks/duplicate/echoes) on Falcon030 & TT might be related to those values.
        readonly static double pal_fps = 50.05270941;
        readonly static double ntsc_fps = 60.03747642;
        readonly static double vga_fps = 60.15;
        readonly static double monochrome_fps = 71.47532613;

        uint target_nb_bitplanes = 4; // 1 to 4
        // uncomment for color
        double fps = vga_fps/2;
        double target_fps = vga_fps/2; // should be >= fps
        // uncomment for monochrome
        //double fps = 30;
        //double target_fps = monochrome_fps; // should be >= fps
        //bool audio_only = true; // true if no video
        //bool audio_mux_only = false; // set to true if you only changed audio
        int first_pic = 0;
        int last_pic = 4662;
        // set to true if you generate a monochrome highres animation. target bitplanes will be forced to 1
        bool highres = false;

        // Original image sequence location
        // don't forget to change it between lowres and highres
        String original_image = @"D:\ankha\320x200c\ankha_{0:0000}.bmp";

        // audio
        int original_samplesize = 2;   // original should always be 16 bits PCM
        int ste_channels = 2;          // 1=mono, 2=stereo (also applies to the input wav file)
        int soundfrq = 25033;       // audio frequency (+/-1Hz depending on the STE main clock). divide by 2 for 25kHz, 4 for 12kHz, etc.
        String soundfile = @"D:\ankha\scratch_25k_16b.wav"; // Original sound file (PCM 16 bit little endian without any tag)

        // Temp files created in step 1
        //String degas_source = @"D:\ankha\ankha{0}bc\ak_";

        // Temp files created in step 2
        //String runtimefile = @"D:\ankha\ankham_run\ankha_{0:00000}.run";
        String runtimesoundfile = @"D:\ankha\ankham_run\ankha_{0:00000}.pcm";

        // Final files 
        String finalvid = @"S:\Emulateurs\Atari ST\HDD_C\DEV\NEW\ankham\asm\audio.dat";
        String finalindex = @"S:\Emulateurs\Atari ST\HDD_C\DEV\NEW\ankham\asm\audio.idx";

        // You can stop here unless you cant to tweak settings in bw_MakeRun.

        public MainWindow()
        {
            InitializeComponent();
            //if (highres) target_nb_bitplanes = 1;
            //degas_source = String.Format(degas_source, (highres?0:target_nb_bitplanes));
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
            //int[] frame = new int[17000];
            //int[] status_original = new int[17000];
            //int[] status = new int[17000];

            //int[] old_frame = new int[17000];
            //int[] old_frame2 = new int[17000];
            //int[] old_frame3;

            //int final_length = 0;
            //int softwareonly_length = 0;

            //byte[] tmpbuf = new byte[50];


            //int final_framecount=(int)(((nb_files-trim_start)/(double)fps)*target_fps);
            //double frame_step = target_fps / (double)fps;

            //if (audio_mux_only)
            //     goto compil;

            //using (System.IO.StreamWriter csv =
            //         new System.IO.StreamWriter(@"D:\ankha\log.csv")) {


            //    for (int pic = trim_start; pic <= nb_files; pic++) {

            //       // int pic = (int)(final_pic / frame_step);
            //        Console.Write(pic+" ");

            //        // System.Threading.Thread.Sleep(1000);

            //        //old_source = source;
            //        old_frame3 = old_frame; // for rollback
            //        old_frame = old_frame2;
            //        old_frame2 = frame;
            //        source = new byte[60000];
            //        frame = new int[17000];

            //        Array.Clear(status_original, 0, status_original.Length);
            //        // status values (comparison with previous frame)
            //        // 0 = no modification
            //        // 1 = modification
            //        // 2 = modification using register optimisation
            //        // 3 = no modification but taken into account for blitter optimization
            //        // 10 = copied with blitter but no modification (wasted time & storage)
            //        // 11 = copied with blitter
            //        // 12 = copied with blitter
            //        // 13 = copied with blitter but no modification (blitter "gap" optimization)
            //        // >15 = blitter fill

            //        // copy into int tab for easier comparisons between 16-bits words
            //        // status=1 if there is a difference with the previous frame

            //        int[] report = new int[status.Length];

            //        Array.Copy(status, report, status.Length);
            //        bw.ReportProgress(0, new Object[] { String.Format(original_image, pic), report });

            //        //using (var runfs = new FileStream(String.Format(runtimefile, final_pic), FileMode.Create, FileAccess.Write)) {
            //        //    tmpbuf[0] = 0;
            //        //    tmpbuf[1] = 0;
            //        //    runfs.Write(tmpbuf, 0, 2);
            //        //}
            //    }
            //}
            

            //Console.WriteLine("Final file: {0} (would be {1} without blitter)", final_length, softwareonly_length);
            ////compil:
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

                            //using (var fs = new FileStream(String.Format(runtimefile, pic), FileMode.Open, FileAccess.Read)) {
                            //    length = (int)fs.Length;
                            //    fs.Read(source, 0, length);
                            //}
                            //final.Write(source, 0, length);
                            //totallength += length;
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
