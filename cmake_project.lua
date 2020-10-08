--
-- Name:        cmake_project.lua
-- Purpose:     Generate a cmake C/C++ project file.
-- Author:      Ryan Pusztai
-- Modified by: Andrea Zanellato
--              Manu Evans
--              Tom van Dijck
--              Yehonatan Ballas
-- Created:     2013/05/06
-- Copyright:   (c) 2008-2020 Jason Perkins and the Premake project
--

local p = premake
local tree = p.tree
local project = p.project
local config = p.config
local cmake = p.modules.cmake

cmake.project = {}
local m = cmake.project


function m.getcompiler(cfg)
	local toolset = p.tools[_OPTIONS.cc or cfg.toolset or p.CLANG]
	if not toolset then
		error("Invalid toolset '" + (_OPTIONS.cc or cfg.toolset) + "'")
	end
	return toolset
end

function m.files(prj)
	local tr = project.getsourcetree(prj)
	tree.traverse(tr, {
		onleaf = function(node, depth)
			_p(depth, '"%s"', node.relpath)
		end
	}, true)
end

--
-- Project: Generate the cmake project file.
--
function m.generate(prj)
	p.utf8()

	if prj.kind == 'StaticLib' then
		_p('add_library("%s"', prj.name)
	elseif prj.kind == 'SharedLib' then
		_p('add_library("%s" SHARED', prj.name)
	else
		_p('add_executable("%s"', prj.name)
	end
	m.files(prj)
	_p(')')
	
	for cfg in project.eachconfig(prj) do
		-- dependencies
		local dependencies = project.getdependencies(prj)
		if #dependencies > 0 then
			_p('add_dependencies("%s"', prj.name)
			for _, dependency in ipairs(dependencies) do
				_p(1, '"%s"', dependency.name)
			end
			_p(')')
		end

		-- output dir
		_p('set_target_properties("%s" PROPERTIES', prj.name)
		_p(1, 'ARCHIVE_OUTPUT_DIRECTORY "%s"', cfg.buildtarget.directory)
		_p(1, 'LIBRARY_OUTPUT_DIRECTORY "%s"', cfg.buildtarget.directory)
		_p(1, 'RUNTIME_OUTPUT_DIRECTORY "%s"', cfg.buildtarget.directory)
		_p(')')

		-- include dirs
		_p('target_include_directories("%s" PUBLIC', prj.name)
		for _, includedir in ipairs(cfg.includedirs) do
			_x(1, '$<$<CONFIG:%s>:%s>', cfg.name, includedir)
		end
		_p(')')
		
		-- defines
		_p('target_compile_definitions("%s" PUBLIC', prj.name)
		for _, define in ipairs(cfg.defines) do
			_p(1, '$<$<CONFIG:%s>:%s>', cfg.name, p.esc(define):gsub(' ', '\\ '))
		end
		_p(')')

		-- lib dirs
		_p('target_link_directories("%s" PUBLIC', prj.name)
		for _, libdir in ipairs(cfg.libdirs) do
			_p(1, '$<$<CONFIG:%s>:%s>', cfg.name, libdir)
		end
		_p(')')

		-- libs
		local toolset = m.getcompiler(cfg)
		_p('target_link_libraries("%s" PUBLIC', prj.name)
		for _, link in ipairs(toolset.getlinks(cfg)) do
			-- CMake can't handle relative paths
			if link:find('/') ~= nil then
				_p(1, '$<$<CONFIG:%s>:%s>', cfg.name, path.getabsolute(prj.location .. '/' .. link))
			else
				_p(1, '$<$<CONFIG:%s>:%s>', cfg.name, link)
			end
		end
		_p(')')

		-- link options
		_p('target_link_options("%s" PUBLIC', prj.name)
		for _, option in ipairs(cfg.linkoptions) do
			_p(1, '$<$<CONFIG:%s>:%s>', cfg.name, option)
		end
		for _, flag in ipairs(toolset.getldflags(cfg)) do
			_p(1, '$<$<CONFIG:%s>:%s>', cfg.name, flag)
		end
		_p(')')

		-- C++ standard
		-- only need to configure it specified
		if cfg.cppdialect and (cfg.cppdialect ~= '' or cfg.cppdialect == 'Default') then
			local standard = {}
			standard["C++98"] = 98
			standard["C++11"] = 11
			standard["C++14"] = 14
			standard["C++17"] = 17
			standard["C++20"] = 20
			standard["gnu++98"] = 98
			standard["gnu++11"] = 11
			standard["gnu++14"] = 14
			standard["gnu++17"] = 17
			standard["gnu++20"] = 20

			local extentions = 'YES'
			if cfg.cppdialect:find('^gnu') == nil then
				extentions = 'NO'
			end
			
			local pic = 'False'
			if cfg.pic == 'On' then
				pic = 'True'
			end

			_p('if(CMAKE_BUILD_TYPE STREQUAL %s)', cfg.name)
			_p(1, 'set_target_properties("%s" PROPERTIES', prj.name)
			_p(2, 'CXX_STANDARD %s', standard[cfg.cppdialect])
			_p(2, 'CXX_STANDARD_REQUIRED YES')
			_p(2, 'CXX_EXTENSIONS %s', extentions)
			_p(2, 'POSITION_INDEPENDENT_CODE %s', pic)
			_p(1, ')')
			_p('endif()')
		end

		-- precompiled headers
		-- copied from gmake2_cpp.lua
		if not cfg.flags.NoPCH and cfg.pchheader then
			local pch = cfg.pchheader
			local found = false

			-- test locally in the project folder first (this is the most likely location)
			local testname = path.join(cfg.project.basedir, pch)
			if os.isfile(testname) then
				pch = project.getrelative(cfg.project, testname)
				found = true
			else
				-- else scan in all include dirs.
				for _, incdir in ipairs(cfg.includedirs) do
					testname = path.join(incdir, pch)
					if os.isfile(testname) then
						pch = project.getrelative(cfg.project, testname)
						found = true
						break
					end
				end
			end

			if not found then
				pch = project.getrelative(cfg.project, path.getabsolute(pch))
			end

			_p('if(CMAKE_BUILD_TYPE STREQUAL %s)', cfg.name)
			_p('target_precompile_headers("%s" PUBLIC %s)', prj.name, pch)
			_p('endif()')
		end
	end
end
