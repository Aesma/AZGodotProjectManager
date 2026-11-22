#pragma once

#include <godot_cpp/classes/node.hpp>

class DemoGameNode : public godot::Node {
    GDCLASS(DemoGameNode, godot::Node)

protected:
    static void _bind_methods() {}

public:
    void _ready() override;
};
