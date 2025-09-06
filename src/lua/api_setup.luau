type Command = { type: string, data: string }

--- Structure for communicating with Zerv
type Api = {
    --- Leave blank for automatic mimetype detection
    return_mimetype: string,
    --- Set the mimetype 
    set_mimetype: (string),
    
    commands: { [number]: Command },
    push_command: (command),

    redirect_url: (string),
    redirect_path: (string),

    return_forbidden: (),
    add_header: (string, string),
}

Smed.api = {
    return_mimetype = "",
    set_mimetype = function(mimetype)
        return_mimetype = mimetype
    end

    commands = {}
    push_command = function(command)
        table.insert(commands, command)
    end

    
}
