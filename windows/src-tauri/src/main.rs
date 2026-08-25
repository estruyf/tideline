// Without this, Windows opens a console window behind the app in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tideline_lib::run()
}
