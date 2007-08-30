/*
 *  QTExport.c
 *  iTunes-LAME
 *
 *  Created by Nicholas Jitkoff on Wed Feb 11 2004.
 *  Copyright (c) 2004 Blacktree, Inc.. All rights reserved.
 *
 */

#include "qtaiff.h"
#import <QuickTime/QuickTime.h>
#import <QuickTime/QTML.h>


OSErr qt_export_to_aiff(const char *infile, const char *outfile) {
    FSSpec in;
    FSSpec out;
    Movie mo = 0;
    OSErr err = 0;
    short frefnum = -1;
    short movie_resid = 0;
    
    NativePathNameToFSSpec(infile,&in,0);
    NativePathNameToFSSpec(outfile,&out,0);
    EnterMovies();
    
    
    
    err = OpenMovieFile(&in,&frefnum,0);
    
    if (err)  return err;
    err = NewMovieFromFile(&mo,frefnum,&movie_resid,0,newMovieActive,0);
    
    if (err) return err;
    err = ConvertMovieToFile(mo,
                             NULL,
                             &out,
                             0L,
                             FOUR_CHAR_CODE('AIFF'),
                             smSystemScript,
                             NULL,
                             NULL,
                             NULL);
    if (err) return err;
    ExitMovies();
    return 0;
}

int main(int argc, const char *argv[]){
    return qt_export_to_aiff(argv[1],argv[2]);
}

