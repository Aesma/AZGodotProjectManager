#include "DemoGameNode.hpp"
#include "SaveStore.hpp"

#include <godot_cpp/variant/utility_functions.hpp>

void DemoGameNode::_ready() {
    godot::UtilityFunctions::print("NativeDemo game node ready: ", get_path(),
            " | SQLite score: ", SaveStore::read_demo_score());
}
