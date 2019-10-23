import { requireNativeComponent, View } from 'react-native';
import React, { Component } from 'react';

const BrightcoveCastButton = requireNativeComponent('BrightcoveCastButton');
class BrightcoveCastButtonComponent extends Component {
    constructor(props) {
        super(props);
    }

    componentDidMount() {

    }

    render() {
        return(
            <View>
            <BrightcoveCastButton 
            style={{
                zIndex: 9999,
                top: 0,
                left: 0,
                width: 50,
                height: 50
            }}/>
            </View>
        )
    }
}

module.exports = BrightcoveCastButtonComponent;
