#include "machomerger_hook.h"
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/fcntl.h>

extern const char *ORIG(_simple_getenv)(const char *envp[], const char *which);
extern int is_blastdoor;

const char *HOOK(_simple_getenv)(const char *envp[], const char *which) {
  if(is_blastdoor) {
    if(strcmp(which, "DYLD_SHARED_REGION") == 0) {
      return "private";
    }
    if(strcmp(which, "DYLD_SHARED_CACHE_DIR") == 0) {
      return "/usr/lib/shared_cache/";
    }
    if(strcmp(which, "DYLD_SHARED_CACHE_DONT_VALIDATE") == 0) {
      return "1";
    }
    if(strcmp(which, "DYLD_INSERT_LIBRARIES") == 0) {
      return (const char *)NULL;
    }
  }
  return ORIG(_simple_getenv)(envp, which);
}