# Spotty.nvim

Display your current playstate, track/artist/duration within the lualine plugin.

![Default Spotty lualine bar](./imgs/bar_default.png)
![Default Spotty lualine bar in different theme](./imgs/bar_default2.png)
![Default Spotty lualine bar in different theme again](./imgs/bar_default3.png)

___

## Warning (Please Read)

This project is in very much early alpha or whatever and is expected to present alot of bugs, so I do not recommend its use if you are looking for a completely stable development environment as of now.

Please report any and all bugs as this helps me iron out this small plugin.

### Installation

Requires Lualine and Plenary as **dependencies**:

```lua
'nvim-lualine/lualine.nvim'
'nvim-lua/plenary.nvim'
```

Install with your preferred package manager.

```lua
'externalhost0/spotty.nvim'
```

Adding two environmental variables is **REQUIRED** for the plugin to function!
As Spotty relies on a Spotify app and the user's client & secret keys.

Creating a Spotify App can be done at their developer dashboard: <https://developer.spotify.com/dashboard>

You must than copy the associated Client ID and Secret for said app, and export them as environmental variables as show below.

```bash
export SPOTIFY_CLIENT_ID="your spotify client id"
export SPOTIFY_CLIENT_SECRET="your spotify client secret"
```

After performing the above steps, your next launch of Neovim will automatically prompt you to grant your created app permissions.

The request for authorization will repeat after an hour as Spotify tokens are only good for one hour.

### Setup

In your lualine configuration just add the component "spotty", this may look something like:

```lua
sections = {
    lualine_x = {
        {
            "spotty"
        },
    }
}
```

I provide a couple options for some extra customization inside lualine
( not implemented yet)

```lua
opts = {

}
```

### Contributing

Feel free to contribute in any way possible, I appreciate any sort of support for small projects like these.
