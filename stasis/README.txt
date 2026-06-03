Stasis - Ender Pearl Stasis System
** Structure
   + Node: Placed at stasis location
   + Client: Run on Ender Pocket Computer
** Features
   + No limit to the number of nodes nor users
   + Node's user cap can be increased by adding more redstone relays
   + Easy configuration & usage
   + Each user can only have one chamber at each node
** Config (Will be asked for required values upon first run)
   + Client
       - user_id: ID of the user
           * Used to ident what chamber to trigger
       - timeout: Timeout in seconds for rednet
       - show_unauthed: Whether to show unauthed nodes
   + Node
       - loc: Location of this node, must be unqiue amongst other nodes
           * Used to ident nodes with a word instaed of the numerical ID
       - def_state: Default state of redstone relays
       - timeout: Timeout in seconds for rednet
       - trigger_time: Time in seconds to trigger relay for
           * 0.2 minimum, can be increased for nether stasis chambers
   * Saved in data/user.cfg
** Commands
   + Client
       - nodes: Query Stasis nodes
       - list: Print found nodes
       - ping [node_id/location]: Ping node and return status
       - tp [node_id/location]: Trigger stasis chamber at specified node
       - config {key} {value}: View entire cfg, view value of key, set key value
       - exit - Exit gracefully
   + Node
       - set [userID] [side] [relayID]: Maps a userID to side of redstone relay
       - clear (user/side) [userID/side] {relayID}: Clears a user from any relay or a side of a specific relay
       - save: Saves config to disk
       - map: Prints current user mappings
       - relays: Prints relay IDs connected
       - config {key} {value}: View entire cfg, view value of key, set key value
       - exit - Exit gracefully

Install with 
wget https://raw.githubusercontent.com/treevar/mc-cc/refs/heads/main/stasis/installer.lua installer.lua
installer {args}
 + nostartup - Don't create startup file
 + run - Run after install
 + node - Install as node
 + client - install as client
 + silent - Don't print
