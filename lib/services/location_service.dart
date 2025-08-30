import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import 'dart:async';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  bool _isLocationEnabled = false;
  bool _hasLocationPermission = false;
  bool _hasBackgroundLocationPermission = false;
  bool _isInitializing = false;
  

  
  // Callbacks for location updates
  Function(Position)? _onLocationUpdate;

  // Getters
  Position? get currentPosition => _currentPosition;
  bool get isLocationEnabled => _isLocationEnabled;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get hasBackgroundLocationPermission => _hasBackgroundLocationPermission;







  Future<bool> checkLocationRequirements() async {
    print('LocationService: Checking location requirements...');
    
    final permissionStatus = await permission_handler.Permission.location.status;
    final backgroundPermissionStatus = await permission_handler.Permission.locationAlways.status;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    _hasLocationPermission = permissionStatus.isGranted;
    _hasBackgroundLocationPermission = backgroundPermissionStatus.isGranted;
    _isLocationEnabled = serviceEnabled;
    
    print('LocationService: Permission granted: $_hasLocationPermission');
    print('LocationService: Background permission granted: $_hasBackgroundLocationPermission');
    print('LocationService: Service enabled: $_isLocationEnabled');
    
    return _hasLocationPermission && _hasBackgroundLocationPermission && _isLocationEnabled;
  }

  Future<permission_handler.PermissionStatus> requestLocationPermission() async {
    print('LocationService: Requesting location permission...');
    
    // Request basic location permission first
    final status = await permission_handler.Permission.location.request();
    _hasLocationPermission = status.isGranted;
    
    // Request background location permission
    if (status.isGranted) {
      final backgroundStatus = await permission_handler.Permission.locationAlways.request();
      _hasBackgroundLocationPermission = backgroundStatus.isGranted;
      
      if (!backgroundStatus.isGranted) {
        print('LocationService: Background location permission denied - critical for 24/7 tracking');
      }
    }
    
    // Also request precise location permission on Android
    if (status.isGranted) {
      try {
        final preciseStatus = await permission_handler.Permission.locationWhenInUse.request();
        print('LocationService: Precise location permission: $preciseStatus');
      } catch (e) {
        print('LocationService: Error requesting precise location: $e');
      }
    }
    
    return status;
  }

  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    Duration? timeout,
  }) async {
    if (_isInitializing) {
      print('LocationService: Already initializing, waiting...');
      await Future.delayed(const Duration(seconds: 2));
    }
    
    _isInitializing = true;
    
    try {
      print('LocationService: Getting current position with ${accuracy.toString()} accuracy...');
      
      // First check if we have permission and service is enabled
      final hasRequirements = await checkLocationRequirements();
      if (!hasRequirements) {
        throw 'Location permission or service not available';
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout ?? const Duration(seconds: 15),
        forceAndroidLocationManager: false, // Use Google Play Services for better accuracy
      );
      
      _currentPosition = position;
      print('LocationService: Position obtained - Lat: ${position.latitude}, Lng: ${position.longitude}, Accuracy: ±${position.accuracy.toStringAsFixed(1)}m');
      
      return position;
    } catch (e) {
      print('LocationService: Error getting current position: $e');
      return null;
    } finally {
      _isInitializing = false;
    }
  }





  // Legacy method for backward compatibility
  void startLocationTracking(Function(Position) onLocationUpdate) {
    print('LocationService: Starting location tracking...');
    
    _onLocationUpdate = onLocationUpdate;
    
    // Stop any existing subscription
    stopLocationTracking();
    
    try {
      // Get initial position first to provide immediate feedback
      getCurrentPosition().then((initialPosition) {
        if (initialPosition != null) {
          print('LocationService: Initial position obtained, starting stream...');
          _onLocationUpdate?.call(initialPosition);
        }
      }).catchError((e) {
        print('LocationService: Error getting initial position: $e');
        // Continue with stream anyway
      });
      
      // Start the position stream with basic settings
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
        timeLimit: Duration(seconds: 30),
      );
      
      _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (position) {
          _currentPosition = position;
          print('LocationService: Update - Lat: ${position.latitude}, Lng: ${position.longitude}, Accuracy: ±${position.accuracy.toStringAsFixed(1)}m');
          
          _onLocationUpdate?.call(position);
        },
        onError: (error) {
          print('LocationService: Stream error: $error');
          
          // Try to restart the stream after a delay
          Timer(const Duration(seconds: 5), () {
            print('LocationService: Attempting to restart location stream...');
            if (_onLocationUpdate != null) {
              startLocationTracking(_onLocationUpdate!);
            }
          });
        },
        cancelOnError: false, // Continue tracking even if there are temporary errors
      );
      
      print('LocationService: Location tracking started successfully');
    } catch (e) {
      print('LocationService: Error starting location tracking: $e');
    }
  }

  void stopLocationTracking() {
    print('LocationService: Stopping location tracking...');
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }





  void dispose() {
    print('LocationService: Disposing...');
    stopLocationTracking();
  }


}