[![License: MIT](https://img.shields.io/packagist/l/doctrine/orm.svg)](https://opensource.org/licenses/MIT)

# Volumetric Lighting
An OpenGL sample that demonstrates Volumetric Lighting using a frustum-aligned voxel grid and compute shaders.

## Screenshots
![VolumetricLighting](data/screenshot.jpg)

## Building

### Windows
Tested on: Windows 10 version 21H1

Prerequisites
* MSVC 19.00 or higher
* CMake 3.8 or higher

```
git clone --recursive https://github.com/diharaw/VolumetricLighting.git
cd VolumetricLighting
mkdir build
cd build
cmake -G "Visual Studio 16 2019" ..
```

## Dependencies
* [dwSampleFramework](https://github.com/diharaw/dwSampleFramework) 

## References
* [Volumetric fog: Unified, compute shader based solution to atmospheric scattering](https://bartwronski.files.wordpress.com/2014/08/bwronski_volumetric_fog_siggraph2014.pdf) 
* [Physically-based & Unified Volumetric Rendering in Frostbite](https://www.ea.com/frostbite/news/physically-based-unified-volumetric-rendering-in-frostbite)

## License
```
Copyright (c) 2021 Dihara Wijetunga

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and 
associated documentation files (the "Software"), to deal in the Software without restriction, 
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, 
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT 
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```