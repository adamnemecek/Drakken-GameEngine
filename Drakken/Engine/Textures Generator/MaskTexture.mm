//
// Created by Allison Lindner on 28/10/15.
// Copyright (c) 2015 Allison Lindner. All rights reserved.
//

#import "MaskTexture.h"
#import "GlobalHeader.h"
#import "b2Math.h"
#import "Box2D.h"
#import <opencv2/opencv.hpp>
#import <vector>
#import <Drakken/Drakken-Swift.h>

@implementation MaskTexture

+ (id<MTLTexture>)generateWithCircleAtPosition:(CGPoint)position withRadius:(int)radius withTextureSize:(CGSize)size {
	CGPoint _position = position;
	_position.x -= size.width / 2.0;
	_position.y -= size.height / 2.0;

	cv::Mat texture = cv::Mat::zeros(cv::Size((int)size.width, (int)size.height), CV_8UC4);
	cv::rectangle(texture, cv::Point(0, 0), cv::Point((int)size.width, (int)size.height), cv::Scalar(0.0, 0.0, 0.0, 0.0), -1);
	cv::circle(texture, cv::Point((int)_position.x, (int)_position.y), radius, cv::Scalar(255.0, 255.0, 255.0, 255.0), -1);

	MTLTextureDescriptor * metalTextureDescriptor =
			[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
															   width:(uint)size.width
															  height:(uint)size.height
														   mipmapped:false];
	id<MTLTexture> metalTexture = [[Core device] newTextureWithDescriptor:metalTextureDescriptor];

	[metalTexture replaceRegion: MTLRegionMake2D(0, 0, (uint)size.width, (uint)size.height)
					mipmapLevel: 0
					  withBytes: texture.ptr()
					bytesPerRow: sizeof(CV_8UC4) * texture.cols];

	return metalTexture;
}

+ (Texture *)cropCircleAtPosition:(CGPoint)position
							withRadius:(int)radius
					  fromMetalTexture:(id<MTLTexture>)metalTexture {
	CGPoint _position = position;
	_position.x += metalTexture.width / 2.0;
	_position.y += metalTexture.height / 2.0;

	uint8_t *rawData = (uint8_t *)calloc(metalTexture.height * metalTexture.width * 4, sizeof(uint8_t));
	[metalTexture getBytes: rawData
			   bytesPerRow: 4 * metalTexture.width
				fromRegion: MTLRegionMake2D(0, 0, metalTexture.width, metalTexture.height)
			   mipmapLevel: 0];
	
	cv::Mat texture = cv::Mat::Mat(
			cv::Size((int)metalTexture.width, (int)metalTexture.height),
			CV_8UC4,
			rawData,
			sizeof(UInt8) * metalTexture.width * 4
	);
	cv::circle(texture, cv::Point((int)_position.x, (int)_position.y), radius, cv::Scalar(0.0, 0.0, 0.0, 0.0), -1);

	MTLTextureDescriptor * metalTextureDescriptor =
			[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
															   width:metalTexture.width
															  height:metalTexture.height
														   mipmapped:false];
	id<MTLTexture> _metalTexture = [[Core device] newTextureWithDescriptor:metalTextureDescriptor];

	[_metalTexture replaceRegion: MTLRegionMake2D(0, 0, metalTexture.width, metalTexture.height)
					mipmapLevel: 0
					  withBytes: texture.ptr()
					bytesPerRow: sizeof(CV_8UC4) * texture.cols];

	texture.release();
	delete [] rawData;
	return [[Texture alloc] initWithMetalTexture: _metalTexture];
}

+ (Rigidbody *)createRigidBodyInWorld:(World *) world
				   withEdgesOfTexture:(id<MTLTexture>) metalTexture
							  Density:(float) density
							 Friction:(float) friction
						  Restitution:(float) restitution
{
	uint8_t *rawData = (uint8_t *)calloc(metalTexture.height * metalTexture.width * 4, sizeof(uint8_t));
	[metalTexture getBytes: rawData
			   bytesPerRow: 4 * metalTexture.width
				fromRegion: MTLRegionMake2D(0, 0, metalTexture.width, metalTexture.height)
			   mipmapLevel: 0];

	cv::Mat texture = cv::Mat(
			cv::Size((int)metalTexture.width, (int)metalTexture.height),
			CV_8UC4,
			rawData,
			sizeof(UInt8) * metalTexture.width * 4
	);
	cv::cvtColor(texture, texture, CV_RGBA2GRAY);

	std::vector<std::vector<cv::Point>> contoursPoints;

	cv::findContours(texture, contoursPoints, CV_RETR_LIST, CV_CHAIN_APPROX_SIMPLE, cv::Point(0, 0));

	Rigidbody * rigidbody = [[Rigidbody alloc] initAtPosition:CGPointZero Radians:0.0 BodyType:BodyType::Static];

	int i, j = 0;
	for(i = 0; i < contoursPoints.size(); i++) {
		for(j = 0; j < contoursPoints[i].size() - 1; j++) {
			[rigidbody addEdgeFixtureWithVector1: CGPointMake(CGFloat(contoursPoints[i][j].x - (metalTexture.width / 2.0)),
							                                  CGFloat(contoursPoints[i][j].y - (metalTexture.height / 2.0)))
										 Vector2: CGPointMake(CGFloat(contoursPoints[i][j + 1].x - (metalTexture.width / 2.0)),
												              CGFloat(contoursPoints[i][j + 1].y - (metalTexture.height / 2.0)))
										 Density: density
										Friction: friction
									 Restitution: restitution];
		}
		[rigidbody addEdgeFixtureWithVector1: CGPointMake(CGFloat(contoursPoints[i][j].x - (metalTexture.width / 2.0)),
						                                  CGFloat(contoursPoints[i][j].y - (metalTexture.height / 2.0)))
									 Vector2: CGPointMake(CGFloat(contoursPoints[0][0].x - (metalTexture.width / 2.0)),
											              CGFloat(contoursPoints[0][0].y - (metalTexture.height / 2.0)))
									 Density: density
									Friction: friction
								 Restitution: restitution];
	}

	[rigidbody createInWorld:world];

	texture.release();
	delete [] rawData;
	return rigidbody;
}

+ (NSArray *) getContoursFromMaskTexture:(id<MTLTexture>) metalTexture withGridSize:(CGSize) size {
	uint8_t *rawData = (uint8_t *)calloc(metalTexture.height * metalTexture.width * 4, sizeof(uint8_t));
	if(size.width > metalTexture.width) {
		size.width = metalTexture.width;
	}
	if(size.height > metalTexture.height) {
		size.height = metalTexture.height;
	}

	int totalStepsWidth = cvCeil(metalTexture.width / size.width);
	int totalStepsHeight = cvCeil(metalTexture.height / size.height);
	int lastSliceWidth = (int)metalTexture.width - ((int)size.width * totalStepsWidth);
	int lastSliceHeight = (int)metalTexture.height - ((int)size.height * totalStepsHeight);

	int stepWidth = 0;
	int stepHeight = 0;
	NSMutableArray *contours = [[NSMutableArray alloc] init];
	for(stepHeight = 0; stepHeight < totalStepsHeight; stepHeight++) {
		for(stepWidth = 0; stepWidth < totalStepsWidth; stepWidth++) {
			int sizeWidth = (uint)stepWidth * (int)size.width;
			int sizeHeight = (uint)stepHeight * (int)size.height;

			if(sizeWidth > metalTexture.width) {
				sizeWidth = lastSliceWidth;
			} else {
				sizeWidth = (int)size.width;
			}

			if(sizeHeight > metalTexture.height) {
				sizeHeight = lastSliceHeight;
			} else {
				sizeHeight = (int)size.height;
			}

			[metalTexture getBytes:rawData
					   bytesPerRow: sizeof(UInt8) * 4 * metalTexture.width
						fromRegion:MTLRegionMake2D(
								(uint)stepWidth * (int)size.width, (uint)stepHeight * (int)size.height,
								(int)sizeWidth, (int)sizeHeight
						)
					   mipmapLevel:0];

			cv::Mat texture = cv::Mat(
					cv::Size((int)metalTexture.width, (int)metalTexture.height),
					CV_8UC4,
					rawData,
					sizeof(UInt8) * metalTexture.width * 4
			);
			cv::cvtColor(texture, texture, CV_RGBA2GRAY);

			std::vector<std::vector<cv::Point>> contoursPoints;

			cv::findContours(texture, contoursPoints, CV_RETR_LIST, CV_CHAIN_APPROX_SIMPLE, cv::Point(0, 0));

			NSMutableArray *contoursSlice = [[NSMutableArray alloc] init];
			for (int i = 0; i < contoursPoints.size(); i++) {
				for (int j = 0; j < contoursPoints[i].size(); j++) {
					CGPoint point = CGPointMake(
							contoursPoints[i][j].x + ((uint)stepWidth * (int)size.width),
							contoursPoints[i][j].y + ((uint)stepHeight * (int)size.height));
					[contoursSlice addObject:[NSValue valueWithCGPoint:point]];
				}
			}
			if(contoursSlice.count > 0) {
				[contours addObject:contoursSlice];
			}
		}
	}
	return contours;
}

@end