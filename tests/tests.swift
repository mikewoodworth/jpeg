import JPEG 

fileprivate
extension Array where Element == UInt8
{
    func load<T, U>(littleEndian:T.Type, as type:U.Type, at byte:Int) -> U
        where T:FixedWidthInteger, U:BinaryInteger
    {
        return self[byte ..< byte + MemoryLayout<T>.size].load(littleEndian: T.self, as: U.self)
    }
}
fileprivate
extension ArraySlice where Element == UInt8
{
    func load<T, U>(littleEndian:T.Type, as type:U.Type) -> U
        where T:FixedWidthInteger, U:BinaryInteger
    {
        return self.withUnsafeBufferPointer
        {
            (buffer:UnsafeBufferPointer<UInt8>) in

            assert(buffer.count >= MemoryLayout<T>.size,
                "attempt to load \(T.self) from slice of size \(buffer.count)")

            var storage:T = .init()
            let value:T   = withUnsafeMutablePointer(to: &storage)
            {
                $0.deinitialize(count: 1)

                let source:UnsafeRawPointer     = .init(buffer.baseAddress!),
                    raw:UnsafeMutableRawPointer = .init($0)

                raw.copyMemory(from: source, byteCount: MemoryLayout<T>.size)

                return raw.load(as: T.self)
            }

            return U(T(littleEndian: value))
        }
    }
}

func testDecode(_ name:String) -> String?
{
    let jpegPath:String = "tests/jpeg/\(name).jpg",
        rgbaPath:String = "tests/rgba/\(name).jpg.rgba"
    return testDecode(jpeg: jpegPath, rgba: rgbaPath)
}

func testDecode(jpeg jpegPath:String, rgba rgbaPath:String) -> String?
{
    do
    {
        guard let rectangular:JPEG.Data.Rectangular = try .decompress(path: jpegPath)
        else
        {
            return "failed to open file '\(jpegPath)'"
        }

        let image:[JPEG.RGB<UInt16>] = rectangular.rgb(of: UInt16.self)

        guard let result:[JPEG.RGB<UInt16>]? =
        (JPEG.File.Source.open(path: rgbaPath)
        {
            let pixels:Int = rectangular.properties.size.x * rectangular.properties.size.y,
                bytes:Int  = pixels * MemoryLayout<JPEG.RGB<UInt16>>.stride

            guard let data:[UInt8] = $0.read(count: bytes)
            else
            {
                return nil
            }

            return (0 ..< pixels).map
            {
                let r:UInt16 = data.load(littleEndian: UInt16.self, as: UInt16.self, at: $0 << 3),
                    g:UInt16 = data.load(littleEndian: UInt16.self, as: UInt16.self, at: $0 << 3 | 2),
                    b:UInt16 = data.load(littleEndian: UInt16.self, as: UInt16.self, at: $0 << 3 | 4)

                return .init(r, g, b)
            }
        })
        else
        {
            return "failed to open file '\(rgbaPath)'"
        }

        guard let reference:[JPEG.RGB<UInt16>] = result
        else
        {
            return "failed to read file '\(rgbaPath)'"
        }

        for (i, pair):(Int, (JPEG.RGB<UInt16>, JPEG.RGB<UInt16>)) in
            zip(image, reference).enumerated()
        {
            guard pair.0 == pair.1
            else
            {
                return "pixel \(i) has value \(pair.0) (expected \(pair.1))"
            }
        }

        return nil
    }
    catch
    {
        return "\(error)"
    }
}

// UNIT TESTS 
 /* 
func testHuffmanTable(leafCounts:[Int], leafValues:[UInt8], message:[UInt8], key:String) -> String?
{
    guard let table:JPEG.HuffmanTable = .build(counts: leafCounts, values: leafValues, target: \.dc.0)
    else 
    {
        return "failed to generate huffman table"
    }
    
    let bits:JPEG.Bitstream = .init(message)
    var b:Int               = 0,
        decoded:String      = ""
    while b < bits.count 
    {
        let entry:JPEG.HuffmanTable.Entry = table[bits[b, count: 16]]
        decoded.append(Character.init(Unicode.Scalar.init(entry.value)))
        b += .init(entry.length)
    }
    
    guard decoded == key
    else 
    {
        return "message decoded incorrectly (expected '\(key)', got '\(decoded)')"
    }
    
    return nil
}

func testHuffmanTableSingle() -> String?
{
    //                  ___0___[root]___1___
    //                /                      \
    //         __0__[ ]__1__            __0__[ ]__1__
    //       /              \         /               \
    //      [a]            [b]      [c]            _0_[ ]_1_
    //                                           /           \
    //                                         [d]        _0_[ ]_1_
    //                                                  /           \
    //                                                [e]        reserved
    
    return testHuffmanTable(leafCounts: [0, 3, 1, 1,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0], 
        leafValues  : .init(0x61 ..< 0x61 + 5), 
        message     : [0b110_1110_0, 0b0_01_10_110], 
        key         : "deabcd")
}
 
func testHuffmanTableDouble() -> String?
{
    // test really skewed tree 
    return testHuffmanTable(leafCounts: [1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1,  1, 1, 1, 1], 
        leafValues  : .init(0x61 ..< 0x61 + 16), 
        message     : [0b1111_1111, 0b1100__1111, 0b1111_1111, 0b1110__1110],
        key         : "kapd")
}
 
func testHuffmanTableUndefined() -> String?
{
    // test codewords that do not correspond to encoded leaf nodes
    return testHuffmanTable(leafCounts: [1, 1, 1, 1,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0], 
        leafValues  : .init(0x61 ..< 0x61 + 4), 
        message     : [0b11110_110, 0b11111110, 0b10_10_1110, 0b11111111, 0b11111110], 
        key         : "\0bbd\0")
}
 
func testHuffmanTableBuilding() -> String? 
{
    guard let table:JPEG.HuffmanTable = .build(
        counts: Examples.HuffmanLuminanceAC.counts, 
        values: Examples.HuffmanLuminanceAC.values, 
        target: \.dc.0)
    else 
    {
        return "failed to generate huffman table"
    }
    
    var expected:UInt8 = 0
    for (length, codeword):(Int, UInt16) in Examples.HuffmanLuminanceAC.codewords 
    {
        let aligned:UInt16 = codeword << (16 - length)
        guard table[aligned].value == expected 
        else 
        {
            return "codeword decoded incorrectly (\(table[aligned].value), expected \(expected))"
        }
        
        if expected & 0x0f < 0x0a 
        {
            expected =  expected & 0xf0          | (expected & 0x0f &+ 1)
        }
        else 
        {
            expected = (expected & 0xf0 &+ 0x10) | (expected & 0xf0 == 0xe0 ? 0 : 1)
        }
    }
    
    return nil
}
 
func testAmplitudeDecoding() -> String? 
{
    for (binade, tail, expected):(Int, UInt16, Int) in 
    [
        (1, 0, -1),
        (1, 1,  1), 
        
        (2, 0, -3), 
        (2, 1, -2), 
        (2, 2,  2), 
        (2, 3,  3),
        
        (5,  0, -31), 
        (5,  1, -30), 
        (5, 14, -17), 
        (5, 15, -16), 
        (5, 16,  16), 
        (5, 17,  17), 
        (5, 30,  30), 
        (5, 31,  31), 
        
        (11,    0, -2047), 
        (11,    1, -2046), 
        (11, 1023, -1024), 
        (11, 1024,  1024), 
        (11, 2046,  2046), 
        (11, 2047,  2047), 
        
        (15,     0, -32767), 
        (15,     1, -32766), 
        (15, 16383, -16384), 
        (15, 16384,  16384), 
        (15, 32766,  32766), 
        (15, 32767,  32767), 
    ]
    {
        let result:Int = JPEG.Bitstream.extend(binade: binade, tail, as: Int.self)
        guard result == expected 
        else 
        {
            return "amplitude decoder mapped level bits {\(binade); \(tail)} incorrectly (expected \(expected), got \(result))"
        }
    }
    
    return nil
} 
 
func testZigZagOrdering() -> String? 
{
    let indices:[[Int]] = 
    [
        [ 0,  1,  5,  6, 14, 15, 27, 28],
        [ 2,  4,  7, 13, 16, 26, 29, 42],
        [ 3,  8, 12, 17, 25, 30, 41, 43],
        [ 9, 11, 18, 24, 31, 40, 44, 53],
        [10, 19, 23, 32, 39, 45, 52, 54], 
        [20, 22, 33, 38, 46, 51, 55, 60], 
        [21, 34, 37, 47, 50, 56, 59, 61], 
        [35, 36, 48, 49, 57, 58, 62, 63]
    ]
    for (y, row):(Int, [Int]) in indices.enumerated() 
    {
        for (x, expected):(Int, Int) in row.enumerated() 
        {
            let z:Int = JPEG.Spectral.Plane.z(x: x, y: y)
            guard z == expected 
            else 
            {
                return "zig-zag transform mapped index (\(x), \(y)) to zig-zag index \(z) (expected \(expected))"
            }
        }
    }
    
    return nil
}  */