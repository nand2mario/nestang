#pragma once
#include <string>

// show or hide OSD
void osd_show(bool show);

// process key and update OSD display 
void osd_update(unsigned char key, bool force = false);
