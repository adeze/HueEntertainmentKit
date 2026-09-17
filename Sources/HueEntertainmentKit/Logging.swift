import Logging

public enum HueLog {
    public static let discovery = Logger(label: "com.adeze.HueEntertainmentKit.discovery")
    public static let client = Logger(label: "com.adeze.HueEntertainmentKit.client")
    public static let session = Logger(label: "com.adeze.HueEntertainmentKit.session")
    public static let transport = Logger(label: "com.adeze.HueEntertainmentKit.transport")
}
