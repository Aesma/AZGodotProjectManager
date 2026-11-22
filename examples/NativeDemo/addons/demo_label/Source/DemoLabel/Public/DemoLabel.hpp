#pragma once

#include <godot_cpp/classes/label.hpp>

class DemoLabel : public godot::Label {
    GDCLASS(DemoLabel, godot::Label)

protected:
    static void _bind_methods() {}

public:
    void _ready() override;
};
