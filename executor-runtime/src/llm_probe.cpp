#include "llama.h"

extern "C" const char * cafeina_llm_probe_version()
{
    return llama_version();
}
