Stasis - Ender Pearl Stasis System
** Structure
   + Node: Placed at stasis location
   + Client: Run on Ender Pocket Computer
** Features
   + No limit to the number of nodes nor users
   + Node's user cap can be increased by adding more redstone relays
   + Easy configuration & usage
   + Each user can only have one chamber at each node
** Config (Will be asked for values upon first run)
   + Client
       - user_id: ID of the user
           * Used to ident what chamber to trigger
   + Node
       - loc: Location of this node, must be unqiue amongst other nodes
           * Used to ident nodes with a word instaed of the numerical ID
   * Saved in data/user.cfg
** Commands
   + Client
       - nodes: Query Stasis nodes
       - list: Print found nodes
       - ping [node_id/location]: Ping node and return status
       - tp [node_id/location]: Trigger stasis chamber at specified node
       - exit - Exit gracefully
   + Node
       - set [userID] [side] [relayID]: Maps a userID to side of redstone relay
       - clear (user/side) [userID/side] {relayID}: Clears a user from any relay or a side of a specific relay
       - save: Saves config to disk
       - map: Prints current user mappings
       - relays: Prints relay IDs connected
       - config {key} {value}: Prints entire config, prints specific key, or sets key's value
       - exit - Exit gracefully

Install with 
wget https://raw.githubusercontent.com/treevar/mc-cc/refs/heads/main/stasis/installer.lua installer.lua
installer {args}
 + nostartup - Don't create startup file
 + run - Run after install
 + node - Install as node
 + client - install as client
