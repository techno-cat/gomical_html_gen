# NAME

gomical_html_gen

# SYNOPSIS

    $ perl gomical_html_gen.pl gomical/json/北海道/札幌市/area.json

# DESCRIPTION

    gomicalリポジトリのJSONから、HTML版のゴミ収集カレンダーを出力するスクリプト

    実行結果はこんな感じ  
    [http://hokkaidopm.github.io/hokkaidopm-casual/gomical_html/](http://hokkaidopm.github.io/hokkaidopm-casual/gomical_html/)

    000〜xxx.htmlとindex.htmlは、gomical_html_gen.plによって出力される
    .
    ├── README.md
    ├── gomical <--- サブモジュール
    ├── gomical_html
    │   ├── 000.html
    │   ├── 001.html
    │   ├── 002.html
    │   ・
    │   ・
    │   ・
    │   ├── 280.html
    │   ├── 281.html
    │   ├── 282.html
    │   ├── css
    │   │   └── main.css
    │   └── index.html
    ├── gomical_html_gen.pl
    └── templates
        ├── calendar.tx
        ├── footer.tx
        ├── index.tx
        └── nnn.tx

# DEPENDENCIES

 - Text::Xslate

# LICENSE

Copyright (C) neko.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

neko techno.cat.miau@gmail.com
