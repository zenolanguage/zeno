// NOTE: This program is written in [Crust](https://github.com/tsoding/Crust).

#![no_std]
#![no_main]
#![allow(dead_code)]
#![allow(non_camel_case_types)]

use core::ffi::*;

macro_rules! c {
  (struct $name:ident < $($gen:ident)+ > { $($field:ident : $type:ty),* $(,)? }) => { #[repr(C)] #[derive(Clone, Copy)] pub struct $name < $($gen)+ > { $($field: $type),* } };
  (struct $name:ident { $($field:ident : $type:ty),* $(,)? }) => { #[repr(C)] #[derive(Clone, Copy)] pub struct $name { $($field: $type),* } };
  (enum $name:ident { $($field:ident = $value:expr),* $(,)? }) => {
    pub enum $name { $($field = $value),* }
    impl $name { fn name(&self) -> String { match self { $($name::$field => c!(stringify!($field))),* } } }
  };
  ($x:expr) => { String{count: $x.len(), data: concat!($x, "\0").as_ptr() as *mut u8} };
}

#[panic_handler] pub unsafe fn panic(_info: &core::panic::PanicInfo) -> ! { abort(); }

c!{struct FILE { unused: c_int }}
extern "C" {
  pub fn fopen(path: *mut u8, mode: *mut u8) -> *mut FILE;
  pub fn fclose(file: *mut FILE) -> c_int;
  pub fn printf(format: *mut u8, ...) -> c_int;
  pub fn abort() -> !;
}

c!{enum Allocator_Mode {
  ALLOC = 0,
  RESIZE = 1,
  FREE = 2,
  FREE_ALL = 3,
}}

c!{struct Allocator {
  proc: fn(data: *mut c_void, mode: Allocator_Mode, old_data: *mut c_void, old_size: usize, new_size: usize) -> *mut c_void,
  data: *mut c_void,
}}

c!{struct Slice<T> {
  count: usize,
  data: *mut T,
}}

impl<T> core::ops::Index<usize> for Slice<T> {
  type Output = T;
  fn index(&self, index: usize) -> &T {
    unsafe { return &*self.data.wrapping_add(index); }
  }
}

type String = Slice<u8>;

c!{struct Array<T> {
  items: Slice<T>,
  capacity: usize,
  allocator: Allocator,
}}

c!{struct IOError{
}}

pub unsafe fn read_entire_file(path: String) -> Result<String, IOError> {
  assert!(path[path.count] == b'\0');
  let file = fopen(path.data, c!("rb").data);
  if !file.is_null() {
    fclose(file);
    return Ok(c!("Hello, world!"));
  }
  Err(IOError{})
}

#[no_mangle]
pub unsafe extern "C" fn main(_argc: c_int, _argv: *mut *mut u8) -> c_int {
  match read_entire_file(c!("zeno.rs")) {
    Ok(src) => _ = printf(c!("%s\n").data, src.data),
    Err(_) => _ = printf(c!("%s\n").data, Allocator_Mode::FREE.name().data),
  }
  0
}
