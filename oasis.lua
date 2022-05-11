local luautf8 = require 'lua-utf8'
local BinaryReader = require 'binarylib.binaryreader'
local BinaryWriter = require 'binarylib.binarywriter'
local utils = require 'binarylib.utils'
local stdio = require 'binarylib.stdio'

local function read_file(filename)
	local file = io.open(filename, 'rb')
	assert(file, string.format('File "%s" not found', filename))
	local data = file:read('*a')
	file:close()
	return data
end

local commands_length = {
	[0x04] = 2,
	[0x05] = 2,
	[0x06] = 2,
	[0x08] = 2,
	[0x0A] = 2,
	[0x0B] = 0,
	[0x0C] = 0,
	[0x0E] = 2,
	[0x0F] = 2,
	[0x09] = 2,
	[0x10] = 2,
	[0x11] = 2,
	[0x12] = 2,
	[0x13] = 2,
	[0x14] = 2,
	[0x15] = 0,
	[0x16] = 0,
	[0x17] = 0,
	[0x18] = 0,
}

local function parse_bytes_string(bytes)
	local br = BinaryReader.new(bytes)
	local result = {}

	while not br:is_eof() do
		local c1 = br:read_ubyte()
		if c1 == 0x7f then
			if br.position % 2 ~= 0 then br.position = br.position + 1 end

			local r1 = br:read_uint16()
			if r1 == 0x0 then
				break
			elseif r1 == 0x01 then
				table.insert(result, '<br>')
			elseif r1 == 0x02 then
				table.insert(result, '<hr>')
			elseif r1 == 0x03 then
				table.insert(result, '<waitbutton>')
			elseif r1 == 0x0D then
				table.insert(result, '<playername>')
			elseif commands_length[r1] then
				local len = commands_length[r1]
				if len > 0 then
					br.position = utils.position_alignment(br.position, 4)
				end

				table.insert(result, '[')
				local codes = {}
				table.insert(codes, string.format("0x%x", r1))

				for _ = 1, len do
					local short = br:read_uint16()
					if short ~= 0x0 then
						table.insert(codes, string.format("0x%x", short))
					end
				end

				table.insert(result, table.concat(codes, ", "))
				table.insert(result, ']')
			elseif r1 == 0x19 then
				br.position = utils.position_alignment(br.position, 4)

				local short1 = br:read_uint16()
				local short2 = br:read_uint16()
				if short1 == 0xffff then
					if short2 == 0xffff then
						table.insert(result, '</span>')
					end
				elseif short1 ~= 0x0 then
					table.insert(result, string.format('<span class="color-%i">', short1))
				else
					table.insert(result, string.format('<span class="color-0">'))
				end
			else
				table.insert(result, '[')
				table.insert(result, string.format("0x%x", r1))
				table.insert(result, ']')
			end
		elseif c1 ~= 0x0 then
			table.insert(result, string.char(c1))
		else
			table.insert(result, '[0x0]')
		end
	end
	return result
end

local function export_gmsg(inputgmsg_name, output_name)
	local data = read_file(inputgmsg_name)
	local binreader = BinaryReader.new(data)
	binreader.position = 0x0C
	local entry_count = binreader:read_int32()
	local pos = binreader:read_int32()

	local msg_array = {}
	binreader.position = pos
	for i = 1, entry_count do
		local id = binreader:read_int32()
		binreader:read_int32()
		local offset = binreader:read_int32()
		local length = binreader:read_int32()
		--print(id, offset, length)

		local prev_position = binreader.position
		binreader.position = offset

		local bytes = binreader:read_bytes(length)
		table.insert(msg_array, {
			id = id,
			length = length,
			bytes = bytes,
		})

		binreader.position = prev_position
	end

	local output_file = io.open(output_name, 'wb')
	for i, v in ipairs(msg_array) do
		local result = parse_bytes_string(v.bytes)
		output_file:write(v.id, "|", table.concat(result), "|\n")
	end
	output_file:close()
end

local function table_find(t, i, value)
	for j = i, #t do
		if t[j] == value then return j end
	end
	assert('index not found with value: ', value)
end

local function write_align2_codepoint(bw, code)
	if bw.position % 2 == 1 then
		bw:write_ubyte(code)
	else
		bw:write_int16(code)
	end
end

local function write_align4_codepoint(bw, code)
	if (bw.position / 2) % 2 == 1 then
		bw:write_int16(code)
		return 0
	else
		bw:write_int32(code)
		return 2
	end
end

local function write_string(id, s, bw)
	local t = {}
	for _, code in luautf8.next, s do
		table.insert(t, luautf8.char(code))
	end

	local i = 1
	while i <= #t do
		local c = t[i]
		if c == '[' then
			local j = table_find(t, i, ']')
			assert(j, string.format('Error in line %i = %s', id, s))
			local temp = table.concat(t, nil, i + 1, j - 1)

			local codes = {}
			for code in temp:gmatch("[^, ]+") do
				table.insert(codes, tonumber(code, 16))
			end
			local first_code = codes[1]
			if first_code == 0x0 then
				bw:write_ubyte(0x0)
			else
				write_align2_codepoint(bw, 0x7f)

				if commands_length[first_code] then
					local len = commands_length[first_code]
					table.remove(codes, 1)
					if len > 0 then
						write_align4_codepoint(bw, first_code)
					else
						bw:write_int16(first_code)
					end
					if first_code == 0x09 then
						bw:write_int16(codes[1])
						bw:write_int16(codes[2])
					else
						for i = 1, len-1 do
							local code = codes[i]
							if code then
								bw:write_int32(code)
							else
								bw:write_int16(0x0)
								bw:write_int16(0x0)
							end
						end
					end
					--[[
					for k = 0, len - 1 do
						if k % 2 == 0 then
							local code = codes[(k / 2) + 1]
							if code then
								bw:write_int16(code)
							else
								bw:write_int16(0x0)
							end
						else
							bw:write_int16(0x0)
						end
					end]]
				else
					local s = ""
					for i, v in ipairs(codes) do
						s = s .. string.format("0x%x", v)
					end
					error(string.format('unrecognized code(s) in line id: %d - %s', id, s))
				end
			end
			i = j
		elseif c == '<' then
			local j = table_find(t, i, '>')
			assert(j, string.format('Error in line %i = %s', id, s))
			local tag = table.concat(t, nil, i + 1, j - 1)

			write_align2_codepoint(bw, 0x7f)

			if tag == 'br' then
				bw:write_int16(0x01)
			elseif tag == 'hr' then
				bw:write_int16(0x02)
			elseif tag == 'waitbutton' then
				bw:write_int16(0x03)
			elseif tag == 'playername' then
				bw:write_int16(0x0D)
			elseif tag:find('span ') then
				local color_value = tag:match('span class="color%-([%d]+)"')
				write_align4_codepoint(bw, 0x19)
				bw:write_int16(tonumber(color_value))
				bw:write_int16(0x0)
			elseif tag:find('/span') then
				write_align4_codepoint(bw, 0x19)
				bw:write_int16(0xffff)
				bw:write_int16(0xffff)
			else
				error(string.format('Invalid tag on %i = %s', id, s))
			end
			i = j
		else
			bw:write_string(c)
		end
		i = i + 1
	end
	write_align2_codepoint(bw, 0x7f)
	return write_align4_codepoint(bw, 0x00)
end

local function import_gmsg(inputgmsg_name, inputmd_name, outputgmsg_name)
	local lines = {}
	for line in io.lines(inputmd_name) do
		if #line > 0 then
			local id, str = line:match('([^|]+)|([^|]*)|')
			assert(id, 'Error in: ' .. line)
			lines[tonumber(id)] = str
		end
	end

	local data = read_file(inputgmsg_name)

	local binreader = BinaryReader.new(data)
	binreader.position = 0x0C
	local entry_count = binreader:read_int32()
	local pos = binreader:read_int32()

	local size = entry_count * 4 * 4 + pos

	local output_file = stdio.open(outputgmsg_name, 'wb')
	local bw = BinaryWriter.from_file(output_file)
	bw:write_raw_bytes(binreader:read_raw_bytes(0, size), size)

	binreader.position = pos
	for i = 1, entry_count do
		local table_pos = binreader.position
		local id = binreader:read_int32()
		local unknown = binreader:read_int32()
		binreader:read_int32()
		binreader:read_int32()

		assert(lines[id], 'Not found: ' .. id)
		local offset = bw.position
		local align = 0
		if #lines[id] > 0 then
			align = write_string(id, lines[id], bw)
			local prev_position = bw.position
			bw.position = table_pos
			bw:write_int32(id)
			bw:write_int32(unknown)
			bw:write_int32(offset)
			bw:write_int32(prev_position - offset - align)
			bw.position = prev_position
		end
	end
end

local first_arg = arg[1]
if first_arg == 'import' then
	assert(arg[2], 'Error: inputgmsg_name arg not found.')
	assert(arg[3], 'Error: inputmd_name arg not found.')
	assert(arg[4], 'Error: outputgmsg_name arg not found.')
	import_gmsg(select(2, unpack(arg)))
elseif first_arg == 'export' then
	assert(arg[2], 'Error: inputgmsg_name arg not found.')
	assert(arg[3], 'Error: output_name arg not found.')
	export_gmsg(select(2, unpack(arg)))
end