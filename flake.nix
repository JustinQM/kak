{
    description = "Justin's Kakoune";

    inputs =
    {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        kak_one =
        {
            url = "git+https://codeberg.org/raiguard/kak-one";
            flake = false;
        };
    };

    outputs = { self, nixpkgs, kak_one }:
    let
        systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
        for_all = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
        packages = for_all (pkgs:
        let
            kak_config = pkgs.runCommand "kak-config" { } ''
                mkdir -p $out
                cp -r ${./config}/. $out/
                chmod -R u+w $out
                mkdir -p $out/colors
                cp ${kak_one}/colors/*.kak $out/colors/
                cp ${kak_one}/LICENSE $out/colors/LICENSE.kak-one
            '';
        in
        {
            default = pkgs.symlinkJoin
            {
                name = "kak";
                paths = [ pkgs.kakoune ];
                nativeBuildInputs = [ pkgs.makeWrapper ];
                postBuild = ''
                    wrapProgram $out/bin/kak \
                        --set-default KAKOUNE_CONFIG_DIR ${kak_config} \
                        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.jujutsu ]}
                '';
                meta.mainProgram = "kak";
            };
        });

        apps = for_all (pkgs:
        {
            default =
            {
                type = "app";
                program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/kak";
            };
        });
    };
}
