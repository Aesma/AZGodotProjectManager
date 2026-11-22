extends RefCounted

# Drain stdout and stderr on each frame so a full pipe never blocks the child.
static func run(tree: SceneTree, executable: String, arguments: PackedStringArray, output: Callable = Callable(), timeout_ms := 0) -> Dictionary:
	var child := OS.execute_with_pipe(executable, arguments, false)
	if child.is_empty():
		return {"code":-1, "text":"无法启动 " + executable}
	var started := Time.get_ticks_msec()
	var streams := [child.stdio, child.stderr]
	var partial := [PackedByteArray(), PackedByteArray()]
	var text := ""
	while true:
		var running := OS.is_process_running(child.pid)
		for i in streams.size():
			var pipe: FileAccess = streams[i]
			var bytes: PackedByteArray = partial[i]
			# Reading a nonblocking pipe yields an empty buffer at EOF. Windows
			# cannot query its length after the child closes the write handle.
			while true:
				var block := pipe.get_buffer(16384)
				bytes.append_array(block)
				if block.size() < 16384: break
			var boundary := bytes.size() if not running else bytes.rfind(10) + 1
			if boundary > 0:
				var chunk := bytes.slice(0, boundary).get_string_from_utf8()
				text = (text + chunk).right(40000)
				if output.is_valid():
					output.call(chunk)
				bytes = bytes.slice(boundary)
			partial[i] = bytes
		if not running:
			return {"code":OS.get_process_exit_code(child.pid), "text":text}
		if timeout_ms > 0 and Time.get_ticks_msec() - started > timeout_ms:
			OS.kill(child.pid)
			return {"code":-1, "text":"读取引擎信息超时。"}
		await tree.process_frame
	return {}

static func build(tree: SceneTree, root: String, tool: String, command: PackedStringArray, output: Callable) -> Dictionary:
	# The CLI discovers project.godot from its working directory. Only the child changes directory.
	if OS.get_name() == "Windows":
		var quoted := PackedStringArray()
		for argument in PackedStringArray([tool]) + command:
			quoted.append("'" + argument.replace("'", "''") + "'")
		var script := "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)\n$ErrorActionPreference='Stop'\nSet-Location -LiteralPath '%s'\n& dotnet %s\nexit $LASTEXITCODE" % [root.replace("'", "''"), " ".join(quoted)]
		var encoded := Marshalls.raw_to_base64(script.to_utf16_buffer())
		return await run(tree, "powershell.exe", ["-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded], output)
	var args := PackedStringArray(["-c", 'cd "$1" && shift && exec "$@"', "AZGodotProjectManager", root, "dotnet", tool])
	args.append_array(command)
	return await run(tree, "/bin/sh", args, output)
