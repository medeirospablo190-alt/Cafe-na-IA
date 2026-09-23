#pragma once

struct lua_State;

namespace cafeina {
namespace world {
class WorldService;
}

void exposeWorldApi(lua_State* L, world::WorldService* service);

} // namespace cafeina
