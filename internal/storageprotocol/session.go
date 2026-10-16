package storageprotocol

import (
	"encoding/json"
	"errors"
	"fmt"
	"sync"
)

var (
	ErrResponseMismatch = errors.New("protocol response request ID mismatch")
	ErrBrokerFailure    = errors.New("storage broker rejected request")
)

// Client serializes a request stream. The worker deliberately permits only
// one in-flight request so each duplicated handle has an unambiguous owner.
type Client struct {
	codec *Codec
	mu    sync.Mutex
	next  uint64
}

func NewClient(codec *Codec) *Client { return &Client{codec: codec, next: 1} }

func (c *Client) Call(operation Operation, payload any, result any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	id := c.next
	if id == 0 {
		return errors.New("protocol request ID exhausted")
	}
	request, err := NewRequest(id, operation, payload)
	if err != nil {
		return err
	}
	if err := c.codec.WriteRequest(request); err != nil {
		return err
	}
	response, err := c.codec.ReadResponse()
	if err != nil {
		return err
	}
	if response.RequestID != id {
		return ErrResponseMismatch
	}
	c.next++
	if !response.OK {
		if response.Error == nil {
			return ErrBrokerFailure
		}
		return fmt.Errorf("%w: %s: %s", ErrBrokerFailure, response.Error.Code, response.Error.Message)
	}
	if result == nil || len(response.Payload) == 0 {
		return nil
	}
	if err := jsonUnmarshal(response.Payload, result); err != nil {
		return fmt.Errorf("decode response payload: %w", err)
	}
	return nil
}

var jsonUnmarshal = json.Unmarshal
