#include "DemoLabel.hpp"
#include "LabelStyle.hpp"

#include <godot_cpp/variant/utility_functions.hpp>

void DemoLabel::_ready() {
    set_text(LabelStyle::welcome_text());
    godot::UtilityFunctions::print("NativeDemo addon label ready: ", get_path(), " | ", get_text());
}
